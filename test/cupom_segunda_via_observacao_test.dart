import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/config_layout_impressao.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/cupom_nao_fiscal_venda_pdf.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_cupom_builder.dart';

const _obsComLogPatio = 'Prox antigo bar de toco\n'
    '[24/09/2026 15:54] RETIRADA_LOJA_PRE_SAIDA por 1 - Mayara: '
    'Retirada (Controle 712): Cimento Poty 50kg x2 Quem retirou: Joao.\n'
    '[24/09/2026 16:10] RETIRADA_FUTURA por 1 - Mayara: '
    'Patio separou nesta loja (baixa estoque): Areia\n'
    'Quem retirou: Joao\n'
    'RETIRADA_LOJA_PRE_SAIDA por sistema';

Venda _vendaComLogPatio() => Venda(
      id: 712,
      numeroControle: 712,
      status: 'finalizada',
      tipoEntrega: 'entrega_loja',
      enderecoEntrega: 'Rua A, 10 | Iolanda | Lauro de Freitas - BA',
      observacaoEntrega: _obsComLogPatio,
      total: 100,
      formaPagamento: 'dinheiro',
    );

List<ItemVenda> _itens() {
  final produto = Produto(
    id: 1,
    codigoInterno: '939',
    nome: 'Cimento Poty 50kg',
    precoCusto: 40,
    precoVenda: 50,
    preco1: 50,
    quantidadeMinima: 0,
    unidade: 'SC',
  );
  return [
    ItemVenda(
      nomeProduto: 'Cimento Poty 50kg',
      quantidade: 2,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: 'entrega_loja',
    )..produto.target = produto,
  ];
}

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

void _semLogPatio(String texto) {
  expect(texto, isNot(contains('RETIRADA_LOJA')));
  expect(texto, isNot(contains('RETIRADA_FUTURA')));
  expect(texto, isNot(contains('Quem retirou')));
  expect(texto, isNot(contains('[24/09/2026')));
  expect(texto, isNot(contains('Patio separou')));
  expect(texto, isNot(contains('Mayara')));
}

void main() {
  test('observacaoEntregaParaCliente mantem so o texto digitado na venda', () {
    expect(
      EntregaVendaHelper.observacaoEntregaParaCliente(_obsComLogPatio),
      ['Prox antigo bar de toco'],
    );
  });

  test('log colado na mesma linha da observacao e cortado', () {
    expect(
      EntregaVendaHelper.observacaoEntregaParaCliente(
        'Prox antigo bar de toco, iolanda '
        '[24/09/2026 15:54] RETIRADA_LOJA_PRE_SAIDA por 1 - May',
      ),
      ['Prox antigo bar de toco, iolanda'],
    );
  });

  test('bloco de entrega imprime apenas OBS/REFERENCIA original', () {
    final linhas = EntregaVendaHelper.linhasBlocoEntregaImpressao(
      venda: _vendaComLogPatio(),
      cliente: Cliente(nomeRazao: 'Maria', telefone: '71982250887'),
      itens: _itens(),
    );
    final obs = linhas.where((l) => l.startsWith('OBS')).toList();
    expect(obs, ['OBS/REFERENCIA: Prox antigo bar de toco']);
    _semLogPatio(linhas.join('\n'));
  });

  test('segunda via ESC/POS omite o historico de retirada do patio', () {
    final venda = _vendaComLogPatio();
    final ascii = _ascii(
      EscPosCupomBuilder.montar(
        CupomBalcaoDados(
          venda: venda,
          config: const EmpresaConfig(nomeLoja: 'Loja'),
          itens: _itens(),
          cliente: Cliente(nomeRazao: 'Maria', telefone: '71982250887'),
          totalRecebido: 100,
          segundaVia: true,
        ),
        largura: EscPosLarguraBobina.mm80,
        abrirGaveta: false,
      ),
    );
    expect(ascii, contains('SEGUNDA VIA'));
    expect(ascii, contains('OBS/REFERENCIA: Prox antigo bar de toco'));
    expect(
      'OBS/REFERENCIA:'.allMatches(ascii).length,
      1,
      reason: 'Somente a observacao digitada na venda vira OBS/REFERENCIA',
    );
    _semLogPatio(ascii);
    expect(
      venda.observacaoEntrega,
      _obsComLogPatio,
      reason: 'Log do patio continua gravado na venda',
    );
  });

  test('segunda via PDF NFC-e gera com observacao contendo log do patio',
      () async {
    final layout = ConfigLayoutImpressao.padraoCupom().copyWith(
      estiloCupomNfce: true,
    );
    final config = EmpresaConfig(
      nomeLoja: 'Loja',
      modeloPdf: 'cupom',
      layoutImpressaoJson: LayoutImpressaoEmpresa(
        cupom: layout,
        orcamento: ConfigLayoutImpressao.padraoOrcamento(),
      ).toJsonString(),
    );
    final pdf = await CupomNaoFiscalVendaPdf.gerar(
      venda: _vendaComLogPatio(),
      config: config,
      itens: _itens(),
      totalRecebido: 100,
      troco: 0,
      segundaVia: true,
    );
    expect(pdf.bytes, isNotEmpty);
  });
}

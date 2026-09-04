import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_cupom_builder.dart';

CupomBalcaoDados _dados(Venda venda) {
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
  final item = ItemVenda(
    nomeProduto: 'Cimento Poty 50kg',
    quantidade: 1,
    precoUnitario: 50,
    precoCustoUnitario: 40,
  )..produto.target = produto;
  return CupomBalcaoDados(
    venda: venda,
    config: const EmpresaConfig(
      nomeLoja: 'Comprou Levou Comercial De Materiais De Construcao',
      telefone: '2136-8582',
      endereco: 'Rua Osvaldo Gordilho, n Sao Cristovao',
      rodapeNota: 'Documento nao fiscal',
    ),
    itens: [item],
    totalRecebido: 50,
  );
}

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

void main() {
  test('cupom dinheiro ESC/POS usa layout DANFE com chave e QR', () {
    final venda = Venda(
      id: 1,
      numeroOrcamento: 1,
      total: 50,
      formaPagamento: 'dinheiro',
    );

    final ascii = _ascii(
      EscPosCupomBuilder.montar(
        _dados(venda),
        largura: EscPosLarguraBobina.mm80,
        abrirGaveta: false,
      ),
    );

    expect(ascii, contains('DANFE NFC-e'));
    expect(ascii, contains('VIA CONSUMIDOR'));
    expect(ascii, contains('CONTIGENCIA'));
    expect(ascii, contains('CHAVE DE ACESSO'));
    expect(ascii, contains('Consulte pela Chave'));
    expect(ascii, contains('QR Code'));
    expect(ascii.toLowerCase(), isNot(contains('cupom nao fiscal')));
    expect(ascii.toLowerCase(), isNot(contains('documento nao fiscal')));
    expect(RegExp(r'\d{4} \d{4}').hasMatch(ascii), isTrue);
  });

  test('NFC-e ESC/POS nao imprime Documento nao fiscal', () {
    const chave = '29260863251482000172650010000000011650080226';
    expect(chave.length, 44);

    final venda = Venda(
      total: 50,
      formaPagamento: 'dinheiro',
      nfceNumero: '1',
      nfceSerie: '1',
      nfceChaveAcesso: chave,
      nfceProtocolo: '123456789012345',
      nfceUrlDanfe: 'http://hinternet.sefaz.ba.gov.br/nfce/consulta?p=$chave',
      nfceEmitidaEm: DateTime(2026, 8, 31, 19, 36, 50),
    );

    final ascii = _ascii(
      EscPosCupomBuilder.montar(
        _dados(venda),
        largura: EscPosLarguraBobina.mm80,
        abrirGaveta: false,
      ),
    );
    expect(ascii.toLowerCase(), isNot(contains('documento nao fiscal')));
    expect(ascii, contains('DANFE NFC-e'));
    expect(ascii, contains('HOMOLOGACAO'));
    expect(ascii, contains('SEM VALOR FISCAL'));
    expect(ascii, contains('VIA CONSUMIDOR'));
    expect(ascii, contains('Protocolo'));
    expect(ascii, contains('Consulte pela Chave'));
    expect(ascii, contains('CHAVE DE ACESSO'));
    expect(ascii, contains('2926'));
    expect(ascii, contains('QR Code'));
  });

  test('CP850 mapeia cedilha e til corretamente', () {
    final comAcento = EscPosCommands.text('CONSTRUÇÃO São');
    expect(comAcento, contains(0x80));
    expect(comAcento, contains(0xC6));
  });
}

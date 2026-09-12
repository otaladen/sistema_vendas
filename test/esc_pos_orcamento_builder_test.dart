import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/orcamento_pdf_service.dart';
import 'package:sistema_vendas/services/esc_pos_commands.dart';
import 'package:sistema_vendas/services/esc_pos_orcamento_builder.dart';

void main() {
  test('orcamento ESC/POS imprime quantidade fracionada em m2', () {
    final produto = Produto(
      id: 2,
      codigoInterno: 'PISO',
      nome: 'Piso ceramico',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 45,
      preco1: 45,
      permiteQuantidadeFracionada: false,
    );
    final armazenado =
        QuantidadeVendaUtil.paraArmazenamento(8.04, fracionada: true);
    final item = ItemVenda(
      nomeProduto: 'Piso ceramico',
      quantidade: armazenado,
      precoUnitario: 45,
      precoCustoUnitario: 30,
      precoTipo: 'preco1',
      tipoEntregaItem: 'retirada',
    )..produto.target = produto;

    expect(
      OrcamentoPdfService.quantidadeComUnidade(item: item, produto: produto),
      '8,04 M2',
    );

    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: Venda(numeroOrcamento: 9, total: 361.8, formaPagamento: 'dinheiro'),
        config: const EmpresaConfig(nomeLoja: 'Loja'),
        itens: [item],
        validadeDias: 7,
        produtosPorItem: {0: produto},
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('8,04 M2'));
    expect(texto, isNot(contains('8 M2 x')));
  });

  test('montar orcamento ESC/POS gera bytes com init e texto', () {
    final produto = Produto(
      id: 1,
      codigoInterno: '39',
      nome: 'Cimento Poly 50kg',
      precoCusto: 40,
      precoVenda: 50,
      preco1: 50,
      quantidadeMinima: 0,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento Poly 50kg',
      quantidade: 1,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      precoTipo: 'preco1',
      tipoEntregaItem: 'retirada',
    )..produto.target = produto;

    final venda = Venda(
      numeroOrcamento: 1,
      total: 50,
      formaPagamento: 'dinheiro',
    );

    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(
          nomeLoja: 'Comprou Levou',
          telefone: '2136-8582',
          endereco: 'Rua Teste',
        ),
        itens: [item],
        validadeDias: 7,
        produtosPorItem: {0: produto},
      ),
      largura: EscPosLarguraBobina.mm80,
    );

    expect(bytes, isNotEmpty);
    expect(bytes[0], 0x1B); // ESC
    expect(bytes[1], 0x40); // @ init
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('ORCAMENTO'));
    expect(texto, contains('Cimento'));
    expect(texto, contains('VALOR TOTAL'));
    expect(texto, contains('COTACAO'));
    expect(texto, contains('CONDICOES DE PAGAMENTO'));
    expect(texto, contains('FORMA SUGERIDA'));
    expect(texto, contains('Pagamento:'));
    expect(texto, contains('Dinheiro'));
    expect(texto, isNot(contains('Dinheiro/PIX/Debito')));
    expect(texto, isNot(contains('2x de')));
    expect(texto, isNot(contains('12x')));
    expect(texto, isNot(contains('Condicoes de parcelamento')));
    expect(texto, isNot(contains('RETIRA LOGO')));
    expect(texto, isNot(contains('RETIRADA FUTURA')));
    expect(texto, isNot(contains('ENTREGA/CARRETO')));
  });

  test('montar orcamento ESC/POS inclui bloco de entrega no carreto', () {
    final item = ItemVenda(
      nomeProduto: 'Areia',
      quantidade: 1,
      precoUnitario: 70,
      precoCustoUnitario: 50,
      tipoEntregaItem: 'entrega_loja',
    );
    final cliente = Cliente(
      nomeRazao: 'Joao Silva',
      telefone: '(21) 99999-8888',
    );
    final venda = Venda(
      numeroOrcamento: 3,
      total: 120,
      tipoEntrega: 'entrega_loja',
      valorFrete: 50,
      enderecoEntrega: 'Rua A, 10 | Centro | Rio - RJ',
      observacaoEntrega: 'Entregar ate 12h',
    );
    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Comprou Levou'),
        itens: [item],
        validadeDias: 7,
        cliente: cliente,
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('DADOS PARA ENTREGA / CARRETO'));
    expect(texto, contains('Joao Silva'));
    expect(texto, contains('99999-8888'));
    expect(texto, contains('Rua A, 10'));
    expect(texto, contains('Entregar ate 12h'));
  });

  test('montar orcamento ESC/POS omite bloco de entrega em cotacao', () {
    final item = ItemVenda(
      nomeProduto: 'Bloco',
      quantidade: 1000,
      precoUnitario: 1.3,
      precoCustoUnitario: 1,
      tipoEntregaItem: 'entrega_loja',
    );
    final venda = Venda(
      numeroOrcamento: 16,
      total: 1633.8,
      tipoEntrega: 'entrega_loja',
      statusEntrega: 'cotacao',
      valorFrete: 50,
    );
    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Comprou Levou'),
        itens: [item],
        validadeDias: 7,
        cliente: Cliente(nomeRazao: 'comprou levou materiais de construcao'),
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, isNot(contains('DADOS PARA ENTREGA / CARRETO')));
    expect(texto, contains('Frete'));
  });

  test('montar orcamento ESC/POS omite bloco de entrega em leva agora', () {
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: 'retirada',
    );
    final venda = Venda(
      numeroOrcamento: 4,
      total: 50,
      tipoEntrega: 'retirada',
    );
    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Comprou Levou'),
        itens: [item],
        validadeDias: 7,
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, isNot(contains('DADOS PARA ENTREGA / CARRETO')));
  });

  test('montar orcamento ESC/POS imprime so o credito escolhido', () {
    final venda = Venda(
      numeroOrcamento: 2,
      total: 90,
      formaPagamento: 'cartao_credito',
      quantidadeParcelas: 3,
    );
    final bytes = EscPosOrcamentoBuilder.montar(
      OrcamentoEscPosDados(
        venda: venda,
        config: const EmpresaConfig(nomeLoja: 'Comprou Levou'),
        itens: const [],
        validadeDias: 7,
      ),
    );
    final texto = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(texto, contains('CONDICOES DE PAGAMENTO'));
    expect(texto, contains('FORMA SUGERIDA'));
    expect(texto, contains('Pagamento:'));
    expect(texto, contains('Cartao de credito'));
    expect(texto, contains('3x de'));
    expect(texto, isNot(contains('2x de')));
    expect(texto, isNot(contains('12x')));
    expect(texto, isNot(contains('A vista')));
    expect(texto, isNot(contains('Dinheiro/PIX/Debito')));
  });
}

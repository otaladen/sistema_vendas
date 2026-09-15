import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/orcamento_totais_impressao.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('parseMoeda aceita num, string pt-BR e nulos', () {
    expect(OrcamentoTotaisImpressao.parseMoeda(null), 0);
    expect(OrcamentoTotaisImpressao.parseMoeda(500), 500);
    expect(OrcamentoTotaisImpressao.parseMoeda('R\$ 1.234,56'), 1234.56);
    expect(OrcamentoTotaisImpressao.parseMoeda('invalido'), 0);
  });

  test('desconto usa total do servidor e itens hidratados, nao itens crus', () {
    final produto = Produto(
      id: 1,
      codigoInterno: 'CIM',
      nome: 'Cimento',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 500,
      preco1: 500,
    );
    final itemHidratado = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 500,
      precoCustoUnitario: 300,
      precoTipo: 'preco1',
    )..produto.target = produto;

    // JSON LanApi sem produto: escala milhar lida como unidade bruta.
    final itemCru = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1000,
      precoUnitario: 500,
      precoCustoUnitario: 300,
      precoTipo: 'preco1',
    );

    final venda = Venda(numeroOrcamento: 1116, total: 500, formaPagamento: 'dinheiro')
      ..itens.add(itemCru);

    expect(venda.descontoImplicitoTotal, greaterThan(1000));

    final totais = OrcamentoTotaisImpressao.calcular(
      venda: venda,
      itens: [itemHidratado],
    );
    expect(totais.subtotalItens, closeTo(500, 0.01));
    expect(totais.desconto, closeTo(0, 0.01));
    expect(totais.total, closeTo(500, 0.01));
    expect(
      OrcamentoTotaisImpressao.imprimirLinhaDesconto(totais.desconto),
      isFalse,
    );
  });

  test('parcelas usam total reconciliado quando ha desconto', () {
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 2,
      precoUnitario: 250,
      precoCustoUnitario: 200,
      precoTipo: 'preco1',
    );
    final venda = Venda(
      numeroOrcamento: 2,
      total: 450,
      formaPagamento: 'cartao_credito',
      quantidadeParcelas: 2,
    );
    final totais = OrcamentoTotaisImpressao.calcular(
      venda: venda,
      itens: [item],
    );
    expect(totais.desconto, closeTo(50, 0.01));
    expect(totais.total, closeTo(450, 0.01));
    expect(totais.total / 2, closeTo(225, 0.01));
  });
}

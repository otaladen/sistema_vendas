import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/relatorio_vendas_service.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('metricas UN com 1553,2 un nao inflam custo nem margem', () {
    const quantidadeArmazenada = 1553200;
    const precoVenda = 3622.10 / 1553.2;
    const precoCusto = 1.50;

    final produto = Produto(
      id: 1,
      codigoInterno: 'P001',
      nome: 'Produto teste',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: precoCusto,
      precoVenda: precoVenda,
      permiteQuantidadeFracionada: false,
    );

    final item = ItemVenda(
      nomeProduto: produto.nome,
      quantidade: quantidadeArmazenada,
      precoUnitario: precoVenda,
      precoCustoUnitario: precoCusto,
      escalaQuantidade: ItemVenda.escalaQuantidadeMilesimos,
    );

    final m = RelatorioVendasService.metricasItemVenda(
      item: item,
      produto: produto,
    );

    expect(m.quantidadeReal, closeTo(1553.2, 0.001));
    expect(m.faturamentoTotal, closeTo(3622.10, 0.05));
    expect(m.custoTotal, closeTo(1553.2 * precoCusto, 0.05));
    expect(m.lucro, closeTo(3622.10 - 1553.2 * precoCusto, 0.05));
    expect(m.margemPercentual, closeTo(35.68, 0.15));
    expect(m.margemIrreal, isFalse);
    expect(m.faturamentoTotal, lessThan(100000));
    expect(m.lucro, lessThan(100000));
  });

  test('margem acima de 1000% e sinalizada como irreal', () {
    final produto = Produto(
      id: 2,
      codigoInterno: 'P002',
      nome: 'Item distorcido',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 1,
      permiteQuantidadeFracionada: false,
    );

    final item = ItemVenda(
      nomeProduto: produto.nome,
      quantidade: 1,
      precoUnitario: 1,
      precoCustoUnitario: 50,
      escalaQuantidade: ItemVenda.escalaQuantidadeLiteral,
    );

    final m = RelatorioVendasService.metricasItemVenda(
      item: item,
      produto: produto,
    );

    expect(m.margemIrreal, isTrue);
    expect(m.margemPercentual, 0);
  });
}

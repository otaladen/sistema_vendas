import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/romaneio_carga_merge.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('Entregas exibe 18,9 e subtotal correto (nao 18900 / 642411)', () {
    final produto = Produto(
      codigoInterno: 'FORM',
      nome: 'Formigres Catavento CL',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 20,
      precoVenda: 33.99,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Formigres Catavento CL',
      quantidade: 18900, // 18,9 m2 em milesimos
      precoUnitario: 33.99,
      precoCustoUnitario: 20,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..carretoReservaAteSaida = true
      ..itens.add(item);

    expect(
      EntregaVendaHelper.quantidadeRomaneioCarga(venda, item),
      18900,
    );
    expect(
      EntregaVendaHelper.quantidadeRomaneioCargaExibicao(venda, item),
      closeTo(18.9, 0.001),
    );
    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioCarga(venda, item),
      '18,9',
    );
    expect(
      EntregaVendaHelper.subtotalRomaneioCarga(venda, item),
      closeTo(18.9 * 33.99, 0.02),
    );
  });

  test('romaneio consolidado formata qtd fracionada', () {
    final produto = Produto(
      codigoInterno: 'AREIA',
      nome: 'Areia',
      unidade: 'M3',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 178,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Areia',
      quantidade: 500,
      precoUnitario: 178,
      precoCustoUnitario: 50,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..carretoReservaAteSaida = true
      ..itens.add(item);

    final linhas = RomaneioCargaMerge.montarLinhas([venda]);
    expect(linhas, hasLength(1));
    expect(linhas.first.quantidadeTotal, 500);
    expect(linhas.first.escalaFracionada, isTrue);
    expect(linhas.first.quantidadeTotalTexto, '0,5');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/relatorios/pendencia_entrega_relatorio.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('lista itens de retirada futura pendente', () {
    final venda = Venda(
      id: 10,
      numeroOrcamento: 100,
      status: 'finalizada',
      tipoEntrega: EntregaVendaHelper.tipoRetiradaFutura,
      entregaPendente: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 5,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      quantidadeJaRetirada: 2,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    );
    venda.itens.add(item);

    final linhas = montarLinhasPendenciaEntrega(
      [venda],
      filtroTipo: TipoPendenciaEntregaRelatorio.retiradaFutura,
    );

    expect(linhas, hasLength(1));
    expect(linhas.first.quantidadePendente, 3);
    expect(linhas.first.tipo, EntregaVendaHelper.tipoRetiradaFutura);
  });

  test('ignora vendas sem pendencia', () {
    final venda = Venda(
      status: 'finalizada',
      entregaPendente: false,
    );
    venda.itens.add(
      ItemVenda(
        nomeProduto: 'X',
        quantidade: 2,
        precoUnitario: 1,
        precoCustoUnitario: 0.5,
        tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
      ),
    );

    final linhas = montarLinhasPendenciaEntrega(
      [venda],
      filtroTipo: TipoPendenciaEntregaRelatorio.todas,
    );

    expect(linhas, isEmpty);
  });
}

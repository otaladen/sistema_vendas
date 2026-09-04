import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('leva agora com quantidadeJaRetirada nao bloqueia cancelamento', () {
    final item = ItemVenda(
      nomeProduto: 'Abracadeira',
      quantidade: 1,
      precoUnitario: 3.5,
      precoCustoUnitario: 1,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
      quantidadeJaRetirada: 1,
    );
    final venda = Venda()
      ..status = 'finalizada'
      ..itens.add(item);

    expect(
      EntregaVendaHelper.vendaTemRetiradaPatioQueBloqueiaCancelamento(
        venda,
        itens: [item],
      ),
      isFalse,
    );
  });

  test('retirada futura com quantidadeJaRetirada bloqueia cancelamento', () {
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 10,
      precoUnitario: 30,
      precoCustoUnitario: 20,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
      quantidadeJaRetirada: 3,
    );
    final venda = Venda()
      ..status = 'finalizada'
      ..itens.add(item);

    expect(
      EntregaVendaHelper.vendaTemRetiradaPatioQueBloqueiaCancelamento(
        venda,
        itens: [item],
      ),
      isTrue,
    );
  });

  test('carreto com quantidadeJaRetirada bloqueia cancelamento', () {
    final item = ItemVenda(
      nomeProduto: 'Areia',
      quantidade: 5,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      quantidadeJaRetirada: 1,
    );
    final venda = Venda()
      ..status = 'finalizada'
      ..itens.add(item);

    expect(
      EntregaVendaHelper.vendaTemRetiradaPatioQueBloqueiaCancelamento(
        venda,
        itens: [item],
      ),
      isTrue,
    );
  });
}

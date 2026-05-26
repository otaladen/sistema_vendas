import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_apply_order.dart';

void main() {
  test('ordenarAlteracoes aplica cliente antes de venda', () {
    final changes = [
      {'entity': 'venda', 'revision': 2},
      {'entity': 'cliente', 'revision': 1},
      {'entity': 'produto', 'revision': 3},
    ];
    SyncApplyOrder.ordenarAlteracoes(changes);
    expect(changes[0]['entity'], 'produto');
    expect(changes[1]['entity'], 'cliente');
    expect(changes[2]['entity'], 'venda');
  });
}

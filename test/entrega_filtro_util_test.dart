import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_filtro_util.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('ehAtrasada ignora entregue e cancelada mas nao complemento pendente', () {
    final ontem = DateTime.now().subtract(const Duration(days: 1));
    final v = Venda(
      status: 'finalizada',
      statusEntrega: 'entregue_complemento_pendente',
      dataEntregaMarcada: ontem,
    );
    expect(EntregaFiltroUtil.ehAtrasada(v), isTrue);

    v.statusEntrega = 'entregue';
    expect(EntregaFiltroUtil.ehAtrasada(v), isFalse);
  });

  test('filtrarPorNumeroNota aceita hash e id', () {
    final v1 = Venda(id: 42, numeroOrcamento: 100);
    final v2 = Venda(id: 99, numeroOrcamento: 0);
    final r = EntregaFiltroUtil.filtrarPorNumeroNota([v1, v2], '#100');
    expect(r, hasLength(1));
    expect(r.first.id, 42);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_lista_api.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  Venda v({
    required int id,
    required String status,
    required DateTime data,
    DateTime? marcada,
  }) {
    return Venda(
      id: id,
      status: 'finalizada',
      statusEntrega: status,
      data: data,
      dataEntregaMarcada: marcada,
    );
  }

  group('EntregaListaApi.priorizarParaHidratacao', () {
    test('nunca corta entrega aberta antiga mesmo com limit baixo', () {
      final antiga = v(
        id: 1,
        status: 'saiu_entrega',
        data: DateTime(2026, 1, 10),
        marcada: DateTime(2026, 1, 11),
      );
      final novasEntregues = [
        for (var i = 0; i < 8; i++)
          v(
            id: 100 + i,
            status: 'entregue',
            data: DateTime(2026, 8, 13).subtract(Duration(hours: i)),
          ),
      ];
      final r = EntregaListaApi.priorizarParaHidratacao(
        [...novasEntregues, antiga],
        limitEntregues: 3,
      );
      expect(r.any((x) => x.id == 1), isTrue);
      expect(r.where((x) => x.statusEntrega == 'entregue'), hasLength(3));
    });

    test('mantem reagendada, pendente e complemento pendente', () {
      final lista = [
        v(id: 1, status: 'reagendada', data: DateTime(2025, 12, 1)),
        v(id: 2, status: 'pendente', data: DateTime(2026, 2, 1)),
        v(
          id: 3,
          status: 'entregue_complemento_pendente',
          data: DateTime(2026, 3, 1),
        ),
        v(id: 4, status: 'entregue', data: DateTime(2026, 8, 1)),
        v(id: 5, status: 'entregue', data: DateTime(2026, 8, 2)),
      ];
      final r = EntregaListaApi.priorizarParaHidratacao(
        lista,
        limitEntregues: 1,
      );
      expect(r.map((x) => x.id), containsAll([1, 2, 3]));
      expect(r.where((x) => x.statusEntrega == 'entregue').single.id, 5);
    });

    test('abertas com data marcada vem antes das sem data', () {
      final semData = v(
        id: 1,
        status: 'pendente',
        data: DateTime(2026, 8, 13),
      );
      final comData = v(
        id: 2,
        status: 'pendente',
        data: DateTime(2026, 1, 1),
        marcada: DateTime(2026, 8, 14),
      );
      final r = EntregaListaApi.priorizarParaHidratacao([semData, comData]);
      expect(r.first.id, 2);
      expect(r.last.id, 1);
    });
  });
}

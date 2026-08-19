import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/listagem_vendas_periodo.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  DateTime utc(int y, int m, int d, [int h = 12]) =>
      DateTime.utc(y, m, d, h);

  Venda venda({
    required DateTime data,
    DateTime? finalizadaEm,
  }) {
    return Venda(
      data: data,
      finalizadaEm: finalizadaEm,
      status: 'finalizada',
      total: 100,
    );
  }

  test('orcamento de segunda faturado na sexta entra no filtro de sexta', () {
    final v = venda(
      data: utc(2026, 8, 10),
      finalizadaEm: utc(2026, 8, 14, 15),
    );
    final ini = utc(2026, 8, 14, 0);
    final fim = DateTime.utc(2026, 8, 14, 23, 59, 59, 999);
    expect(
      ListagemVendasPeriodo.noIntervaloUtc(v, inicioUtc: ini, fimUtc: fim),
      isTrue,
    );
  });

  test('venda so com data da nota ainda entra no dia da nota', () {
    final v = venda(data: utc(2026, 8, 10));
    final ini = utc(2026, 8, 10, 0);
    final fim = DateTime.utc(2026, 8, 10, 23, 59, 59, 999);
    expect(
      ListagemVendasPeriodo.noIntervaloUtc(v, inicioUtc: ini, fimUtc: fim),
      isTrue,
    );
  });

  test('fora do periodo por data e por finalizacao fica de fora', () {
    final v = venda(
      data: utc(2026, 8, 1),
      finalizadaEm: utc(2026, 8, 2),
    );
    final ini = utc(2026, 8, 14, 0);
    final fim = DateTime.utc(2026, 8, 14, 23, 59, 59, 999);
    expect(
      ListagemVendasPeriodo.noIntervaloUtc(v, inicioUtc: ini, fimUtc: fim),
      isFalse,
    );
  });
}

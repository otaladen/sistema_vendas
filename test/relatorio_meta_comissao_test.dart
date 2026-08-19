import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/relatorio_meta_comissao.dart';

void main() {
  test('meta proporcional de um mes inteiro equivale a meta mensal', () {
    final meta = relatorioMetaProporcionalPeriodo(
      metaMensal: 31000,
      inicio: DateTime(2026, 1, 1),
      fim: DateTime(2026, 1, 31),
    );
    expect(meta, closeTo(31000, 0.01));
  });

  test('meta proporcional de 10 dias de janeiro e 10/31 da mensal', () {
    final meta = relatorioMetaProporcionalPeriodo(
      metaMensal: 31000,
      inicio: DateTime(2026, 1, 1),
      fim: DateTime(2026, 1, 10),
    );
    expect(meta, closeTo(10000, 0.01));
  });

  test('meta proporcional cruza virada de mes', () {
    final meta = relatorioMetaProporcionalPeriodo(
      metaMensal: 30000,
      inicio: DateTime(2026, 1, 31),
      fim: DateTime(2026, 2, 1),
    );
    expect(meta, closeTo(30000 / 31 + 30000 / 28, 0.01));
  });

  test('comissao com base negativa fica no piso zero', () {
    expect(relatorioComissaoPisoZero(-800, 5), 0);
    expect(relatorioComissaoPisoZero(1000, 5), closeTo(50, 0.001));
    expect(relatorioComissaoPisoZero(1000, 0), 0);
  });
}

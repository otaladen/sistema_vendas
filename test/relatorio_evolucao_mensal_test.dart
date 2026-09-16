import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/relatorio_evolucao_mensal.dart';

void main() {
  group('limitesPeriodoEvolucao', () {
    final agora = DateTime(2026, 9, 15, 10, 30);

    test('ultimos 6 meses inclui o mes corrente e 5 anteriores', () {
      final lim = limitesPeriodoEvolucao(
        EvolucaoPeriodoPreset.ultimos6,
        agora: agora,
      );
      expect(lim.$1, DateTime(2026, 4, 1));
      expect(lim.$2.year, 2026);
      expect(lim.$2.month, 9);
      expect(lim.$2.day, 15);
      expect(listarPrimeirosDiasMes(lim.$1, lim.$2), hasLength(6));
    });

    test('ultimos 12 meses atravessa o ano', () {
      final lim = limitesPeriodoEvolucao(
        EvolucaoPeriodoPreset.ultimos12,
        agora: agora,
      );
      expect(lim.$1, DateTime(2025, 10, 1));
      expect(listarPrimeirosDiasMes(lim.$1, lim.$2), hasLength(12));
    });

    test('ano atual comeca em janeiro', () {
      final lim = limitesPeriodoEvolucao(
        EvolucaoPeriodoPreset.anoAtual,
        agora: agora,
      );
      expect(lim.$1, DateTime(2026, 1, 1));
      expect(listarPrimeirosDiasMes(lim.$1, lim.$2), hasLength(9));
    });
  });

  test('limitesDoMes corta o mes corrente em fimGeral', () {
    final lim = limitesDoMes(DateTime(2026, 9, 1), DateTime(2026, 9, 15, 23, 59));
    expect(lim.$1, DateTime(2026, 9, 1));
    expect(lim.$2.day, 15);
  });

  test('montarEvolucaoMensal preenche meses sem venda com zero', () {
    final serie = montarEvolucaoMensal(
      preset: EvolucaoPeriodoPreset.ultimos6,
      inicio: DateTime(2026, 4, 1),
      fim: DateTime(2026, 9, 15, 23, 59, 59, 999),
      totaisDoMes: (ini, fim) {
        if (ini.month == 6) {
          return const EvolucaoTotaisMes(
            faturamento: 1200,
            lucro: 300,
            qtdNotas: 4,
          );
        }
        return const EvolucaoTotaisMes(faturamento: 0, lucro: 0, qtdNotas: 0);
      },
    );
    expect(serie.meses, hasLength(6));
    expect(serie.totalFaturamento, 1200);
    expect(serie.totalNotas, 4);
    expect(serie.mediaMensal, closeTo(200, 0.001));
    expect(serie.melhorMes?.mes, 6);
    expect(serie.melhorMes?.rotuloCurto, 'jun/26');
    expect(serie.piorMesComVenda?.mes, 6);
  });

  test('variacaoMesAnterior e formatacao', () {
    final meses = [
      RelatorioMesFaturamento(
        ano: 2026,
        mes: 7,
        inicio: DateTime(2026, 7, 1),
        fim: DateTime(2026, 7, 31),
        faturamento: 100,
        lucro: 10,
        qtdNotas: 1,
      ),
      RelatorioMesFaturamento(
        ano: 2026,
        mes: 8,
        inicio: DateTime(2026, 8, 1),
        fim: DateTime(2026, 8, 31),
        faturamento: 150,
        lucro: 20,
        qtdNotas: 2,
      ),
    ];
    expect(variacaoMesAnterior(meses, 0), isNull);
    expect(variacaoMesAnterior(meses, 1), closeTo(50, 0.01));
    expect(formatarVariacaoMes(50), '+50.0%');
    expect(formatarVariacaoMes(null), '—');
  });
}

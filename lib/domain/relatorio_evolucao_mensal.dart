/// Tipo de grafico na evolucao mensal de vendas.
enum EvolucaoGraficoTipo { barras, linhas, area }

/// Recorte temporal da evolucao mensal.
enum EvolucaoPeriodoPreset { ultimos6, ultimos12, anoAtual }

/// Faturamento consolidado de um mes (vendas finalizadas + ajuste de devolucao/troca).
class RelatorioMesFaturamento {
  const RelatorioMesFaturamento({
    required this.ano,
    required this.mes,
    required this.inicio,
    required this.fim,
    required this.faturamento,
    required this.lucro,
    required this.qtdNotas,
  });

  final int ano;
  final int mes;
  final DateTime inicio;
  final DateTime fim;
  final double faturamento;
  final double lucro;
  final int qtdNotas;

  DateTime get referencia => DateTime(ano, mes, 1);

  String get rotuloCurto {
    const abrev = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    final m = mes.clamp(1, 12);
    final aa = (ano % 100).toString().padLeft(2, '0');
    return '${abrev[m - 1]}/$aa';
  }

  String get rotuloLongo {
    const nomes = [
      'Janeiro',
      'Fevereiro',
      'Marco',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final m = mes.clamp(1, 12);
    return '${nomes[m - 1]}/$ano';
  }
}

/// Totais mensais usados na consolidacao (espelha RelatorioTotaisPeriodo).
class EvolucaoTotaisMes {
  const EvolucaoTotaisMes({
    required this.faturamento,
    required this.lucro,
    required this.qtdNotas,
  });

  final double faturamento;
  final double lucro;
  final int qtdNotas;
}

/// Serie mensal + totais do periodo.
class RelatorioEvolucaoMensal {
  const RelatorioEvolucaoMensal({
    required this.inicio,
    required this.fim,
    required this.preset,
    required this.meses,
  });

  final DateTime inicio;
  final DateTime fim;
  final EvolucaoPeriodoPreset preset;
  final List<RelatorioMesFaturamento> meses;

  double get totalFaturamento =>
      meses.fold<double>(0, (s, m) => s + m.faturamento);

  double get totalLucro => meses.fold<double>(0, (s, m) => s + m.lucro);

  int get totalNotas => meses.fold<int>(0, (s, m) => s + m.qtdNotas);

  double get mediaMensal =>
      meses.isEmpty ? 0 : totalFaturamento / meses.length;

  RelatorioMesFaturamento? get melhorMes {
    if (meses.isEmpty) return null;
    return meses.reduce(
      (a, b) => a.faturamento >= b.faturamento ? a : b,
    );
  }

  RelatorioMesFaturamento? get piorMesComVenda {
    final comVenda = meses.where((m) => m.faturamento.abs() >= 0.01).toList();
    if (comVenda.isEmpty) return null;
    return comVenda.reduce((a, b) => a.faturamento <= b.faturamento ? a : b);
  }

  bool get temFaturamento => totalFaturamento.abs() >= 0.01 || totalNotas > 0;

  String get rotuloPeriodo {
    switch (preset) {
      case EvolucaoPeriodoPreset.ultimos6:
        return 'Ultimos 6 meses';
      case EvolucaoPeriodoPreset.ultimos12:
        return 'Ultimos 12 meses';
      case EvolucaoPeriodoPreset.anoAtual:
        return 'Ano atual';
    }
  }
}

/// Calcula o intervalo do preset (mes corrente incluso, ate o fim do dia de [agora]).
(DateTime inicio, DateTime fim) limitesPeriodoEvolucao(
  EvolucaoPeriodoPreset preset, {
  DateTime? agora,
}) {
  final now = agora ?? DateTime.now();
  final fim = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  switch (preset) {
    case EvolucaoPeriodoPreset.ultimos6:
      return (DateTime(now.year, now.month - 5, 1), fim);
    case EvolucaoPeriodoPreset.ultimos12:
      return (DateTime(now.year, now.month - 11, 1), fim);
    case EvolucaoPeriodoPreset.anoAtual:
      return (DateTime(now.year, 1, 1), fim);
  }
}

/// Primeiro dia de cada mes coberto por [inicio]..[fim] (inclusive).
List<DateTime> listarPrimeirosDiasMes(DateTime inicio, DateTime fim) {
  var cursor = DateTime(inicio.year, inicio.month, 1);
  final ultimo = DateTime(fim.year, fim.month, 1);
  final out = <DateTime>[];
  while (!cursor.isAfter(ultimo)) {
    out.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return out;
}

/// Intervalo do mes de [primeiroDia], cortado em [fimGeral] (mes corrente incompleto).
(DateTime inicio, DateTime fim) limitesDoMes(
  DateTime primeiroDia,
  DateTime fimGeral,
) {
  final ini = DateTime(primeiroDia.year, primeiroDia.month, 1);
  final fimMes = DateTime(
    primeiroDia.year,
    primeiroDia.month + 1,
    0,
    23,
    59,
    59,
    999,
  );
  final fim = fimMes.isAfter(fimGeral) ? fimGeral : fimMes;
  return (ini, fim);
}

/// Variacao percentual do mes [indice] contra o anterior (nulo no primeiro).
double? variacaoMesAnterior(List<RelatorioMesFaturamento> meses, int indice) {
  if (indice <= 0 || indice >= meses.length) return null;
  final atual = meses[indice].faturamento;
  final anterior = meses[indice - 1].faturamento;
  if (anterior.abs() < 0.01) {
    if (atual.abs() < 0.01) return 0;
    return null;
  }
  return ((atual - anterior) / anterior.abs()) * 100;
}

String formatarVariacaoMes(double? pct) {
  if (pct == null) return '—';
  if (pct.abs() < 0.05) return '0%';
  final sinal = pct >= 0 ? '+' : '';
  return '$sinal${pct.toStringAsFixed(1)}%';
}

/// Monta a serie mensal a partir de totais ja calculados por mes.
RelatorioEvolucaoMensal montarEvolucaoMensal({
  required EvolucaoPeriodoPreset preset,
  required DateTime inicio,
  required DateTime fim,
  required EvolucaoTotaisMes Function(DateTime inicioMes, DateTime fimMes)
      totaisDoMes,
}) {
  final refs = listarPrimeirosDiasMes(inicio, fim);
  final meses = <RelatorioMesFaturamento>[];
  for (final ref in refs) {
    final lim = limitesDoMes(ref, fim);
    meses.add(
      mesDeTotais(
        primeiroDia: ref,
        fimGeral: fim,
        totais: totaisDoMes(lim.$1, lim.$2),
      ),
    );
  }
  return RelatorioEvolucaoMensal(
    inicio: inicio,
    fim: fim,
    preset: preset,
    meses: meses,
  );
}

RelatorioMesFaturamento mesDeTotais({
  required DateTime primeiroDia,
  required DateTime fimGeral,
  required EvolucaoTotaisMes totais,
}) {
  final lim = limitesDoMes(primeiroDia, fimGeral);
  return RelatorioMesFaturamento(
    ano: primeiroDia.year,
    mes: primeiroDia.month,
    inicio: lim.$1,
    fim: lim.$2,
    faturamento: totais.faturamento,
    lucro: totais.lucro,
    qtdNotas: totais.qtdNotas,
  );
}

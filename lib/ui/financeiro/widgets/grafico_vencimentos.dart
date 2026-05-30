import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/conta_pagar.dart';
import '../../../data/titulo_receber_repository.dart';
import '../../../main.dart';
import '../../../objectbox.g.dart';

/// Totais de [valorParcela] por faixa de vencimento (contas **PENDENTE** ou **ATRASADO**).
@immutable
class ContasPagarVencimentosBuckets {
  const ContasPagarVencimentosBuckets({
    required this.atrasadas,
    required this.proximos7Dias,
    required this.de8a15Dias,
    required this.de16a30Dias,
  });

  final double atrasadas;
  final double proximos7Dias;
  final double de8a15Dias;
  final double de16a30Dias;

  static const ContasPagarVencimentosBuckets zero =
      ContasPagarVencimentosBuckets(
        atrasadas: 0,
        proximos7Dias: 0,
        de8a15Dias: 0,
        de16a30Dias: 0,
      );

  double get somaTotal =>
      atrasadas + proximos7Dias + de8a15Dias + de16a30Dias;
}

/// Agrupa contas em aberto por vencimento (calendário local → data UTC meia-noite).
ContasPagarVencimentosBuckets computeContasPagarVencimentosBuckets(
  Box<ContaPagar> box,
) {
  final hojeLocal = DateTime.now();
  final hoje = DateTime.utc(
    hojeLocal.year,
    hojeLocal.month,
    hojeLocal.day,
  );
  final fim7 = hoje.add(const Duration(days: 6));
  final ini8 = hoje.add(const Duration(days: 7));
  final fim15 = hoje.add(const Duration(days: 14));
  final ini16 = hoje.add(const Duration(days: 15));
  final fim30 = hoje.add(const Duration(days: 29));

  DateTime normalizaDia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  final cond = ContaPagar_.status.equals(ContaPagarStatus.pendente).or(
    ContaPagar_.status.equals(ContaPagarStatus.atrasado),
  );
  final q = box.query(cond).build();
  try {
    var atras = 0.0;
    var p7 = 0.0;
    var p815 = 0.0;
    var p1630 = 0.0;

    for (final c in q.find()) {
      final v = c.valorParcela;
      if (!v.isFinite || v <= 0) continue;
      final venc = normalizaDia(c.dataVencimento);
      if (venc.isBefore(hoje)) {
        atras += v;
      } else if (!venc.isAfter(fim7)) {
        p7 += v;
      } else if (!venc.isBefore(ini8) && !venc.isAfter(fim15)) {
        p815 += v;
      } else if (!venc.isBefore(ini16) && !venc.isAfter(fim30)) {
        p1630 += v;
      }
    }
    return ContasPagarVencimentosBuckets(
      atrasadas: atras,
      proximos7Dias: p7,
      de8a15Dias: p815,
      de16a30Dias: p1630,
    );
  } finally {
    q.close();
  }
}

/// Agrupa titulos a receber (fiado) em aberto por vencimento.
ContasPagarVencimentosBuckets computeTitulosReceberVencimentosBuckets(
  List<TituloReceberResumoLinha> titulos,
) {
  final hojeLocal = DateTime.now();
  final hoje = DateTime.utc(
    hojeLocal.year,
    hojeLocal.month,
    hojeLocal.day,
  );
  final fim7 = hoje.add(const Duration(days: 6));
  final ini8 = hoje.add(const Duration(days: 7));
  final fim15 = hoje.add(const Duration(days: 14));
  final ini16 = hoje.add(const Duration(days: 15));
  final fim30 = hoje.add(const Duration(days: 29));

  DateTime normalizaDia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  var atras = 0.0;
  var p7 = 0.0;
  var p815 = 0.0;
  var p1630 = 0.0;

  for (final l in titulos) {
    if (l.titulo.saldo <= 0.001) continue;
    final v = l.titulo.saldo;
    final venc = normalizaDia(l.titulo.vencimento);
    if (venc.isBefore(hoje)) {
      atras += v;
    } else if (!venc.isAfter(fim7)) {
      p7 += v;
    } else if (!venc.isBefore(ini8) && !venc.isAfter(fim15)) {
      p815 += v;
    } else if (!venc.isBefore(ini16) && !venc.isAfter(fim30)) {
      p1630 += v;
    }
  }
  return ContasPagarVencimentosBuckets(
    atrasadas: atras,
    proximos7Dias: p7,
    de8a15Dias: p815,
    de16a30Dias: p1630,
  );
}

/// Gráfico de barras: vencimentos x saldo de referência em caixa.
class GraficoVencimentosContasPagar extends StatelessWidget {
  const GraficoVencimentosContasPagar({
    super.key,
    required this.buckets,
    this.saldoCaixaAtual,
    this.altura = 260,
    this.titulo = 'Fluxo de vencimentos (em aberto)',
    this.subtituloVazio =
        'Nenhum valor pendente ou atrasado nas faixas exibidas.',
  });

  final ContasPagarVencimentosBuckets buckets;
  final double? saldoCaixaAtual;
  final double altura;
  final String titulo;
  final String subtituloVazio;

  static final NumberFormat _moedaCurta = NumberFormat.compactSimpleCurrency(
    locale: 'pt_BR',
    name: 'BRL',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = theme.extension<AppSemanticColors>();

    final corAtraso = semantic?.errorFg ?? const Color(0xFF9B1C1C);
    final cor7 = scheme.primary;
    final cor815 = scheme.primary.withValues(alpha: 0.72);
    final cor1630 = scheme.outline;

    final valores = [
      buckets.atrasadas,
      buckets.proximos7Dias,
      buckets.de8a15Dias,
      buckets.de16a30Dias,
    ];
    final maxBar = valores.fold<double>(
      0,
      (m, e) => e > m ? e : m,
    );
    final saldoRef = saldoCaixaAtual;
    final maxYRaw = [
      maxBar,
      if (saldoRef != null && saldoRef.isFinite && saldoRef > 0) saldoRef,
    ].fold<double>(0, (m, e) => e > m ? e : m);
    final maxY = maxYRaw <= 0 ? 1.0 : maxYRaw * 1.12;

    final mostrarLinhaSaldo =
        saldoRef != null && saldoRef.isFinite && saldoRef > 0;
    final saldoLinha = mostrarLinhaSaldo ? saldoRef : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _LegendaSaldoCaixa(
              saldo: saldoRef,
              totalTitulos: buckets.somaTotal,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: altura,
              child: buckets.somaTotal <= 0.004
                  ? Center(
                      child: Text(
                        subtituloVazio,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final rodWidth = (c.maxWidth / 14).clamp(10.0, 22.0);
                        final barGroups = <BarChartGroupData>[
                          for (var i = 0; i < valores.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: valores[i] <= 0 ? 0 : valores[i],
                                  width: rodWidth,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                  ),
                                  color: [corAtraso, cor7, cor815, cor1630][i],
                                ),
                              ],
                            ),
                        ];

                        return BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: maxY,
                            minY: 0,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxY > 0 ? maxY / 4 : null,
                              getDrawingHorizontalLine: (v) => FlLine(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.35,
                                ),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            extraLinesData: ExtraLinesData(
                              extraLinesOnTop: true,
                              horizontalLines: [
                                if (saldoLinha != null)
                                  HorizontalLine(
                                    y: saldoLinha,
                                    dashArray: const [6, 4],
                                    strokeWidth: 2,
                                    color: const Color(0xFF0D9488),
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: const Color(0xFF0F766E),
                                        fontWeight: FontWeight.w700,
                                      ),
                                      labelResolver: (_) =>
                                          'Saldo caixa ${_moedaCurta.format(saldoLinha)}',
                                    ),
                                  ),
                              ],
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    const labels = [
                                      'Atrasadas',
                                      '≤ 7 dias',
                                      '8–15 dias',
                                      '16–30 dias',
                                    ];
                                    if (i < 0 || i >= labels.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        labels[i],
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: scheme.onSurface.withValues(
                                            alpha: 0.75,
                                          ),
                                          height: 1.1,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 44,
                                  interval: maxY > 0 ? maxY / 4 : null,
                                  getTitlesWidget: (value, meta) {
                                    if (value <= 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      _moedaCurta.format(value),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) =>
                                    scheme.surfaceContainerHighest,
                                getTooltipItem:
                                    (group, groupIndex, rod, rodIndex) {
                                  const labels = [
                                    'Atrasadas',
                                    'Próximos 7 dias',
                                    '8 a 15 dias',
                                    '16 a 30 dias',
                                  ];
                                  final xi = group.x.toInt();
                                  final v = valores[xi];
                                  return BarTooltipItem(
                                    '${labels[xi]}\n'
                                    '${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v)}',
                                    TextStyle(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                            ),
                            barGroups: barGroups,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendaSaldoCaixa extends StatelessWidget {
  const _LegendaSaldoCaixa({
    required this.saldo,
    required this.totalTitulos,
  });

  final double? saldo;
  final double totalTitulos;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = saldo;
    late final String textoSaldo;
    final double? diff;
    if (s != null && s.isFinite) {
      textoSaldo = _moeda.format(s);
      diff = totalTitulos - s;
    } else {
      textoSaldo = 'não informado';
      diff = null;
    }

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Saldo atual em caixa: $textoSaldo',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        if (diff != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              'Títulos no gráfico − saldo: ${_moeda.format(diff)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
    );
  }
}

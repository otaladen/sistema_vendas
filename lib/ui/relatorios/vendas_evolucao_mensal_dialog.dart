import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../services/pdf_evolucao_vendas_mensal.dart';
import '../layout/app_layout.dart';
import '../theme/app_relatorio_cores.dart';
import 'relatorio_evolucao_mensal.dart';
import 'relatorio_helpers.dart';
import 'relatorio_pdf_acoes.dart';
import 'relatorio_periodo.dart';

/// Dialogo / tela de evolucao mensal de vendas (ultimos 6-12 meses ou ano atual).
class VendasEvolucaoMensalDialog extends StatefulWidget {
  const VendasEvolucaoMensalDialog({
    super.key,
    required this.vendaRepository,
  });

  final dynamic vendaRepository;

  /// Abre como dialogo largo no desktop ou pagina no leiaute compacto.
  static Future<void> abrir(
    BuildContext context, {
    required dynamic vendaRepository,
  }) {
    if (context.isDesktopLayout) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 840),
            child: VendasEvolucaoMensalDialog(
              vendaRepository: vendaRepository,
            ),
          ),
        ),
      );
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VendasEvolucaoMensalDialog(
          vendaRepository: vendaRepository,
        ),
      ),
    );
  }

  @override
  State<VendasEvolucaoMensalDialog> createState() =>
      _VendasEvolucaoMensalDialogState();
}

class _VendasEvolucaoMensalDialogState extends State<VendasEvolucaoMensalDialog> {
  final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final NumberFormat _moedaCurta = NumberFormat.compactSimpleCurrency(
    locale: 'pt_BR',
    name: 'BRL',
  );

  EvolucaoPeriodoPreset _preset = EvolucaoPeriodoPreset.ultimos12;
  EvolucaoGraficoTipo _tipo = EvolucaoGraficoTipo.barras;
  RelatorioEvolucaoMensal? _serie;
  bool _carregando = true;
  bool _exportando = false;
  String _erro = '';

  @override
  void initState() {
    super.initState();
    unawaited(_carregar());
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = '';
    });
    final limites = limitesPeriodoEvolucao(_preset);
    try {
      await relatorioHidratarPeriodoApi(
        widget.vendaRepository,
        (limites.$1, limites.$2),
      );
    } catch (e) {
      _erro = '$e';
    }
    if (!mounted) return;
    setState(() {
      _serie = consolidarEvolucaoMensal(
        widget.vendaRepository,
        preset: _preset,
      );
      _carregando = false;
    });
  }

  String _fmt(double v) => _moeda.format(v);

  Future<void> _imprimirPdf() async {
    final serie = _serie;
    if (serie == null) return;
    setState(() => _exportando = true);
    try {
      await RelatorioPdfAcoes.imprimirBytes(
        context,
        bytes: () => gerarPdfEvolucaoVendasMensal(
          serie: serie,
          tipoGrafico: _tipo,
        ),
        mensagemSeVazio: 'Nada para imprimir.',
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _salvarPdf() async {
    final serie = _serie;
    if (serie == null) return;
    setState(() => _exportando = true);
    try {
      await RelatorioPdfAcoes.salvarBytes(
        context,
        bytes: () => gerarPdfEvolucaoVendasMensal(
          serie: serie,
          tipoGrafico: _tipo,
        ),
        nomeArquivoSemExtensao: 'evolucao_vendas_mensal',
        mensagemSeVazio: 'Nada para exportar.',
      );
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = AppRelatorioCores.cor(
      context,
      AppRelatorioId.vendasEvolucaoMensal,
    );
    final emDialogo = context.findAncestorWidgetOfExactType<Dialog>() != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !emDialogo,
        leading: emDialogo
            ? IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              )
            : null,
        title: const Text('Grafico de vendas dos ultimos meses'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : () => unawaited(_carregar()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Salvar PDF',
            onPressed: _serie == null || _exportando ? null : _salvarPdf,
            icon: const Icon(Icons.save_alt_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<EvolucaoPeriodoPreset>(
                        segments: const [
                          ButtonSegment(
                            value: EvolucaoPeriodoPreset.ultimos6,
                            label: Text('Ultimos 6 meses'),
                            icon: Icon(Icons.calendar_view_month_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: EvolucaoPeriodoPreset.ultimos12,
                            label: Text('Ultimos 12 meses'),
                            icon: Icon(Icons.date_range_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: EvolucaoPeriodoPreset.anoAtual,
                            label: Text('Ano atual'),
                            icon: Icon(Icons.event_outlined, size: 18),
                          ),
                        ],
                        selected: {_preset},
                        onSelectionChanged: (s) {
                          setState(() => _preset = s.first);
                          unawaited(_carregar());
                        },
                      ),
                      SegmentedButton<EvolucaoGraficoTipo>(
                        segments: const [
                          ButtonSegment(
                            value: EvolucaoGraficoTipo.barras,
                            label: Text('Barras'),
                            icon: Icon(Icons.bar_chart_outlined, size: 18),
                          ),
                          ButtonSegment(
                            value: EvolucaoGraficoTipo.linhas,
                            label: Text('Linhas'),
                            icon: Icon(Icons.show_chart, size: 18),
                          ),
                          ButtonSegment(
                            value: EvolucaoGraficoTipo.area,
                            label: Text('Area'),
                            icon: Icon(Icons.area_chart_outlined, size: 18),
                          ),
                        ],
                        selected: {_tipo},
                        onSelectionChanged: (s) {
                          setState(() => _tipo = s.first);
                        },
                      ),
                      FilledButton.icon(
                        onPressed: _serie == null || _exportando
                            ? null
                            : _imprimirPdf,
                        icon: _exportando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: const Text('Imprimir / Gerar PDF'),
                      ),
                    ],
                  ),
                  if (widget.vendaRepository is VendaApiRepository &&
                      widget.vendaRepository.relatorioJanelaTruncada) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Periodo grande demais no terminal: o relatorio pode estar '
                      'incompleto. Confira no PC servidor ou use 6 meses.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  if (_erro.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _erro,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_carregando) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _carregando && _serie == null
                ? const Center(child: CircularProgressIndicator())
                : _buildConteudo(context, cor),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudo(BuildContext context, Color destaque) {
    final serie = _serie;
    if (serie == null) {
      return const Center(child: Text('Nao foi possivel montar o relatorio.'));
    }
    final theme = Theme.of(context);
    final desktop = context.isDesktopLayout;

    final grafico = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Faturamento mensal · ${serie.rotuloPeriodo}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              formatarIntervaloPeriodo((serie.inicio, serie.fim)),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: !serie.temFaturamento
                  ? Center(
                      child: Text(
                        'Nenhuma venda finalizada neste periodo.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : _GraficoEvolucaoMensal(
                      serie: serie,
                      tipo: _tipo,
                      formatarEixo: _moedaCurta.format,
                      formatarTooltip: _fmt,
                    ),
            ),
          ],
        ),
      ),
    );

    final resumo = Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              'Resumo numerico',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: serie.meses.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = serie.meses[i];
                final varPct = variacaoMesAnterior(serie.meses, i);
                final melhor = serie.melhorMes;
                final ehMelhor = melhor != null &&
                    melhor.ano == m.ano &&
                    melhor.mes == m.mes &&
                    serie.temFaturamento;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: ehMelhor
                        ? destaque.withValues(alpha: 0.18)
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${m.mes}'.padLeft(2, '0'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ehMelhor ? destaque : null,
                      ),
                    ),
                  ),
                  title: Text(
                    m.rotuloLongo,
                    style: TextStyle(
                      fontWeight: ehMelhor ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${m.qtdNotas} nota(s)'
                    '${varPct == null ? '' : ' · ${formatarVariacaoMes(varPct)}'}',
                  ),
                  trailing: Text(
                    _fmt(m.faturamento),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _kpis(context, serie, destaque),
          const SizedBox(height: 12),
          Expanded(
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: grafico),
                      const SizedBox(width: 12),
                      SizedBox(width: 340, child: resumo),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(height: 280, child: grafico),
                      const SizedBox(height: 12),
                      Expanded(child: resumo),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(
    BuildContext context,
    RelatorioEvolucaoMensal serie,
    Color destaque,
  ) {
    final melhor = serie.melhorMes;
    final cards = [
      _kpiCard(
        context,
        rotulo: 'Faturamento',
        valor: _fmt(serie.totalFaturamento),
        icone: Icons.payments_outlined,
        cor: destaque,
      ),
      _kpiCard(
        context,
        rotulo: 'Media mensal',
        valor: _fmt(serie.mediaMensal),
        icone: Icons.stacked_line_chart,
        cor: destaque,
      ),
      _kpiCard(
        context,
        rotulo: 'Melhor mes',
        valor: melhor == null || !serie.temFaturamento
            ? '—'
            : melhor.rotuloCurto,
        detalhe: melhor == null || !serie.temFaturamento
            ? null
            : _fmt(melhor.faturamento),
        icone: Icons.emoji_events_outlined,
        cor: destaque,
      ),
      _kpiCard(
        context,
        rotulo: 'Notas',
        valor: '${serie.totalNotas}',
        icone: Icons.receipt_long_outlined,
        cor: destaque,
      ),
    ];
    if (context.isCompactLayout) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 8),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 8),
              Expanded(child: cards[3]),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required String rotulo,
    required String valor,
    required IconData icone,
    required Color cor,
    String? detalhe,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: cor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rotulo, style: theme.textTheme.labelSmall),
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (detalhe != null)
                    Text(detalhe, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraficoEvolucaoMensal extends StatelessWidget {
  const _GraficoEvolucaoMensal({
    required this.serie,
    required this.tipo,
    required this.formatarEixo,
    required this.formatarTooltip,
  });

  final RelatorioEvolucaoMensal serie;
  final EvolucaoGraficoTipo tipo;
  final String Function(double) formatarEixo;
  final String Function(double) formatarTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxVal = serie.meses.fold<double>(
      0,
      (m, e) => e.faturamento > m ? e.faturamento : m,
    );
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.18;
    final intervalo = maxY / 4;
    final cor = scheme.primary;

    Widget rotuloInferior(double value, TitleMeta meta) {
      final i = value.round();
      if (i < 0 || i >= serie.meses.length) return const SizedBox.shrink();
      final pular = serie.meses.length > 8 && i.isOdd;
      if (pular) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          serie.meses[i].rotuloCurto,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    AxisTitles eixoY() => AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            interval: intervalo,
            getTitlesWidget: (value, meta) {
              if (value < 0 || value > maxY + 0.01) {
                return const SizedBox.shrink();
              }
              return Text(
                formatarEixo(value),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              );
            },
          ),
        );

    final grades = FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: intervalo,
      getDrawingHorizontalLine: (v) => FlLine(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        strokeWidth: 1,
      ),
    );

    if (tipo == EvolucaoGraficoTipo.barras) {
      return LayoutBuilder(
        builder: (context, c) {
          final rodWidth = (c.maxWidth / (serie.meses.length * 2.1))
              .clamp(10.0, 28.0);
          return BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              minY: 0,
              gridData: grades,
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (group.x < 0 || group.x >= serie.meses.length) {
                      return null;
                    }
                    final m = serie.meses[group.x];
                    return BarTooltipItem(
                      '${m.rotuloLongo}\n${formatarTooltip(m.faturamento)}',
                      theme.textTheme.labelMedium!.copyWith(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: eixoY(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: rotuloInferior,
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < serie.meses.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: serie.meses[i].faturamento <= 0
                            ? 0
                            : serie.meses[i].faturamento,
                        width: rodWidth,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: cor.withValues(alpha: 0.82),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      );
    }

    final spots = [
      for (var i = 0; i < serie.meses.length; i++)
        FlSpot(i.toDouble(), serie.meses[i].faturamento.clamp(0, double.infinity)),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (serie.meses.length - 1).clamp(0, 100).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: grades,
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spotsTouched) {
              return [
                for (final s in spotsTouched)
                  LineTooltipItem(
                    '${serie.meses[s.x.round()].rotuloLongo}\n'
                    '${formatarTooltip(s.y)}',
                    theme.textTheme.labelMedium!.copyWith(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ];
            },
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: eixoY(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: rotuloInferior,
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: cor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: tipo == EvolucaoGraficoTipo.linhas || serie.meses.length <= 8,
            ),
            belowBarData: BarAreaData(
              show: tipo == EvolucaoGraficoTipo.area,
              color: cor.withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

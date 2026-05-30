import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/venda_repository.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_horarios_pico_helper.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioHorariosPicoPage extends StatefulWidget {
  const RelatorioHorariosPicoPage({
    super.key,
    required this.vendaRepository,
  });

  final VendaRepository vendaRepository;

  @override
  State<RelatorioHorariosPicoPage> createState() =>
      _RelatorioHorariosPicoPageState();
}

class _LinhaHora {
  const _LinhaHora({
    required this.hora,
    required this.quantidade,
    required this.percentual,
  });

  final int hora;
  final int quantidade;
  final double percentual;
}

class _RelatorioHorariosPicoPageState extends State<RelatorioHorariosPicoPage> {
  LimitesPeriodo? _limites;
  ResumoHorariosPico? _resumo;
  List<_LinhaHora> _linhas = [];

  void _calcular(LimitesPeriodo limites) {
    final vendas =
        relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final resumo = relatorioCalcularHorariosPico(vendas);
    final linhas = <_LinhaHora>[
      for (var h = 0; h < 24; h++)
        _LinhaHora(
          hora: h,
          quantidade: resumo.vendasNaHora(h),
          percentual: resumo.percentualNaHora(h),
        ),
    ]..sort((a, b) => b.quantidade.compareTo(a.quantidade));

    setState(() {
      _limites = limites;
      _resumo = resumo;
      _linhas = linhas;
    });
  }

  List<List<String>> _linhasCsv() {
    final r = _resumo;
    if (r == null) return const [];
    return [
      ['Hora', 'Faixa', 'Vendas', '% do total'],
      for (var h = 0; h < 24; h++)
        [
          '${h.toString().padLeft(2, '0')}:00',
          relatorioFormatarFaixaHoraria(h),
          '${r.vendasNaHora(h)}',
          r.percentualNaHora(h).toStringAsFixed(1),
        ],
      if (r.totalVendas > 0) ...[
        [],
        [
          'Pico',
          relatorioFormatarFaixaHoraria(r.horaPico),
          '${r.vendasNaHoraPico}',
          r.percentualNaHora(r.horaPico).toStringAsFixed(1),
        ],
      ],
    ];
  }

  List<String> _paginasPdf() {
    final lim = _limites;
    final r = _resumo;
    if (lim == null || r == null) return [];
    final linhasPdf = _linhas
        .where((l) => l.quantidade > 0)
        .map(
          (l) => [
            relatorioFormatarRotuloHoraEixo(l.hora),
            relatorioFormatarFaixaHoraria(l.hora),
            '${l.quantidade}',
            '${l.percentual.toStringAsFixed(1)}%',
          ],
        )
        .toList();
    return relatorioMontarPaginasTabela(
      titulo: 'HORARIOS DE PICO — NUMERO DE VENDAS',
      subtitulo: '${formatarIntervaloPeriodo(lim)} · '
          'Pico: ${relatorioFormatarFaixaHoraria(r.horaPico)} '
          '(${r.vendasNaHoraPico} vendas)',
      cabecalho: ['Hora', 'Faixa', 'Vendas', '%'],
      linhas: linhasPdf,
    );
  }

  Widget _buildGrafico(BuildContext context, ResumoHorariosPico resumo) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = resumo.vendasPorHora.reduce((a, b) => a > b ? a : b);
    if (maxY <= 0) {
      return const SizedBox.shrink();
    }
    final yMax = (maxY * 1.15).ceilToDouble().clamp(1.0, double.infinity);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendas por hora do dia',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, c) {
                  final rodWidth = (c.maxWidth / 28).clamp(8.0, 16.0);
                  return BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: yMax,
                      minY: 0,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: yMax > 4 ? yMax / 4 : 1,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 2,
                            getTitlesWidget: (value, meta) {
                              final h = value.toInt();
                              if (h < 0 || h > 23 || h.isOdd) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  relatorioFormatarRotuloHoraEixo(h),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: yMax > 4 ? yMax / 4 : 1,
                            getTitlesWidget: (value, meta) {
                              if (value != value.roundToDouble()) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                value.toInt().toString(),
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
                      barGroups: [
                        for (var h = 0; h < 24; h++)
                          BarChartGroupData(
                            x: h,
                            barRods: [
                              BarChartRodData(
                                toY: resumo.vendasNaHora(h).toDouble(),
                                width: rodWidth,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                                color: h == resumo.horaPico
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                      ],
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

  Widget _buildDestaquePico(BuildContext context, ResumoHorariosPico resumo) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (resumo.totalVendas <= 0) {
      return Text(
        'Nenhuma venda finalizada no periodo selecionado.',
        style: theme.textTheme.bodyMedium,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Maior movimento',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${relatorioFormatarFaixaHoraria(resumo.horaPico)} · '
            '${resumo.vendasNaHoraPico} venda(s)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${resumo.totalVendas} vendas no periodo · '
            '${resumo.percentualNaHora(resumo.horaPico).toStringAsFixed(1)}% '
            'concentradas nesse horario',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final resumo = _resumo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horarios de pico'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'horarios_pico_vendas',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: _calcular,
            onAtualizar: lim != null ? () => _calcular(lim) : null,
            resumo: lim == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatarIntervaloPeriodo(lim),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (resumo != null) ...[
                        const SizedBox(height: 8),
                        _buildDestaquePico(context, resumo),
                      ],
                    ],
                  ),
          ),
          if (resumo != null && resumo.totalVendas > 0)
            _buildGrafico(context, resumo),
          const Divider(height: 1),
          Expanded(
            child: resumo == null || resumo.totalVendas <= 0
                ? const Center(child: Text('Nenhuma venda no periodo.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _linhas.where((l) => l.quantidade > 0).length,
                    itemBuilder: (context, i) {
                      final linhasVisiveis =
                          _linhas.where((l) => l.quantidade > 0).toList();
                      final r = linhasVisiveis[i];
                      final ehPico = r.hora == resumo.horaPico;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: ehPico
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(
                          relatorioFormatarFaixaHoraria(r.hora),
                          style: ehPico
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                        subtitle: Text(
                          '${r.percentual.toStringAsFixed(1)}% do total no periodo',
                        ),
                        trailing: Text(
                          '${r.quantidade} venda(s)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

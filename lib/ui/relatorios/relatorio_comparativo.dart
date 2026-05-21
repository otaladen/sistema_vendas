import 'package:flutter/material.dart';

import '../../data/venda_repository.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';

/// Totais consolidados de um intervalo (vendas finalizadas + ajuste dev/troca).
class RelatorioTotaisPeriodo {
  const RelatorioTotaisPeriodo({
    required this.faturamento,
    required this.lucro,
    required this.qtdNotas,
  });

  final double faturamento;
  final double lucro;
  final int qtdNotas;

  double get ticketMedio => qtdNotas == 0 ? 0 : faturamento / qtdNotas;

  double get margemPct =>
      faturamento.abs() < 0.01 ? 0 : (lucro / faturamento) * 100;
}

/// Periodo imediatamente anterior com a mesma duracao (em dias).
LimitesPeriodo relatorioPeriodoAnterior(LimitesPeriodo atual) {
  final ini = DateTime(
    atual.$1.year,
    atual.$1.month,
    atual.$1.day,
  );
  final fimDia = DateTime(
    atual.$2.year,
    atual.$2.month,
    atual.$2.day,
  );
  final dias = fimDia.difference(ini).inDays + 1;
  final fimAnt = ini.subtract(const Duration(days: 1));
  final fimAntEnd = DateTime(
    fimAnt.year,
    fimAnt.month,
    fimAnt.day,
    23,
    59,
    59,
    999,
  );
  final iniAnt = fimAntEnd.subtract(Duration(days: dias - 1));
  final iniAntStart = DateTime(iniAnt.year, iniAnt.month, iniAnt.day);
  return (iniAntStart, fimAntEnd);
}

RelatorioTotaisPeriodo relatorioTotaisPeriodo(
  VendaRepository repo,
  LimitesPeriodo limites,
) {
  final vendas = relatorioVendasFinalizadasPeriodo(repo, limites);
  final fatNotas = vendas.fold<double>(0, (s, v) => s + v.total);
  final lucNotas = vendas.fold<double>(0, (s, v) => s + v.lucroTotal);
  final imp = repo.calcularImpactosDevolucaoTrocaPeriodo(
    relatorioPeriodoFiltro(limites),
  );
  return RelatorioTotaisPeriodo(
    faturamento: fatNotas + imp.impactoFaturamentoTotal,
    lucro: lucNotas + imp.impactoLucroTotal,
    qtdNotas: vendas.length,
  );
}

String relatorioFormatarVariacaoPct(double atual, double anterior) {
  if (anterior.abs() < 0.01) {
    if (atual.abs() < 0.01) return '—';
    return '+100%';
  }
  final pct = ((atual - anterior) / anterior.abs()) * 100;
  final sinal = pct >= 0 ? '+' : '';
  return '$sinal${pct.toStringAsFixed(1)}%';
}

Color? relatorioCorVariacao(BuildContext context, double atual, double anterior) {
  final delta = atual - anterior;
  if (delta.abs() < 0.01) return null;
  return delta > 0
      ? Colors.green.shade700
      : Theme.of(context).colorScheme.error;
}

/// KPIs com opcao de comparar ao periodo anterior equivalente.
class RelatorioKpiComparativo extends StatelessWidget {
  const RelatorioKpiComparativo({
    super.key,
    required this.atual,
    this.anterior,
    required this.formatarMoeda,
    this.mostrarComparativo = false,
  });

  final RelatorioTotaisPeriodo atual;
  final RelatorioTotaisPeriodo? anterior;
  final String Function(double) formatarMoeda;
  final bool mostrarComparativo;

  Widget _kpi(
    BuildContext context, {
    required String rotulo,
    required String valorAtual,
    required double rawAtual,
    required double rawAnterior,
  }) {
    final ant = anterior;
    final comp = mostrarComparativo && ant != null;
    final varPct = comp ? relatorioFormatarVariacaoPct(rawAtual, rawAnterior) : null;
    final cor = comp
        ? relatorioCorVariacao(context, rawAtual, rawAnterior)
        : null;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rotulo,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                valorAtual,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (comp) ...[
                const SizedBox(height: 2),
                Text(
                  'Ant.: ${rotulo.contains('Notas') ? '${rawAnterior.toInt()}' : formatarMoeda(rawAnterior)} · $varPct',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ant = anterior;
    return Row(
      children: [
        _kpi(
          context,
          rotulo: 'Faturamento',
          valorAtual: formatarMoeda(atual.faturamento),
          rawAtual: atual.faturamento,
          rawAnterior: ant?.faturamento ?? 0,
        ),
        const SizedBox(width: 8),
        _kpi(
          context,
          rotulo: 'Lucro',
          valorAtual: formatarMoeda(atual.lucro),
          rawAtual: atual.lucro,
          rawAnterior: ant?.lucro ?? 0,
        ),
        const SizedBox(width: 8),
        _kpi(
          context,
          rotulo: 'Notas',
          valorAtual: '${atual.qtdNotas}',
          rawAtual: atual.qtdNotas.toDouble(),
          rawAnterior: (ant?.qtdNotas ?? 0).toDouble(),
        ),
      ],
    );
  }
}

/// Switch padrao para ligar comparativo de periodo.
class RelatorioSwitchComparativo extends StatelessWidget {
  const RelatorioSwitchComparativo({
    super.key,
    required this.value,
    required this.onChanged,
    this.periodoAnterior,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final LimitesPeriodo? periodoAnterior;

  @override
  Widget build(BuildContext context) {
    final rotulo = periodoAnterior != null
        ? 'Comparar com ${formatarIntervaloPeriodo(periodoAnterior!)}'
        : 'Comparar com periodo anterior';
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(rotulo),
      subtitle: const Text('Mesma duracao em dias, imediatamente antes'),
      value: value,
      onChanged: onChanged,
    );
  }
}

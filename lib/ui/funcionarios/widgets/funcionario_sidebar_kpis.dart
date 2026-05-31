import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// KPIs compactos no topo da sidebar (notebooks 15").
class FuncionarioSidebarKpis extends StatelessWidget {
  const FuncionarioSidebarKpis({
    super.key,
    required this.totalCadastrados,
    required this.totalAtivos,
    required this.folhaBaseAtivos,
  });

  final int totalCadastrados;
  final int totalAtivos;
  final double folhaBaseAtivos;

  static final _moeda = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: _MiniKpi(
              rotulo: 'Cad.',
              valor: '$totalCadastrados',
              cor: const Color(0xFF455A64),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniKpi(
              rotulo: 'Ativos',
              valor: '$totalAtivos',
              cor: const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _MiniKpi(
              rotulo: 'Folha',
              valor: _moeda.format(folhaBaseAtivos),
              cor: const Color(0xFF1565C0),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({
    required this.rotulo,
    required this.valor,
    required this.cor,
  });

  final String rotulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

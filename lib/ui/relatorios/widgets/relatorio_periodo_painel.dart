import 'package:flutter/material.dart';

import '../relatorio_periodo.dart';

/// Painel superior padrao: periodo + resumo opcional + area de filtros extras.
class RelatorioPeriodoPainel extends StatelessWidget {
  const RelatorioPeriodoPainel({
    super.key,
    required this.onPeriodoChanged,
    this.filtrosExtras = const [],
    this.resumo,
    this.onAtualizar,
    this.labelPeriodo = 'Periodo',
  });

  final void Function(LimitesPeriodo limites) onPeriodoChanged;
  final List<Widget> filtrosExtras;
  final Widget? resumo;
  final VoidCallback? onAtualizar;
  final String labelPeriodo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RelatorioSeletorPeriodo(
                    label: labelPeriodo,
                    onChanged: onPeriodoChanged,
                  ),
                ),
                if (onAtualizar != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: onAtualizar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
            if (filtrosExtras.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...filtrosExtras,
            ],
            if (resumo != null) ...[
              const SizedBox(height: 8),
              resumo!,
            ],
          ],
        ),
      ),
    );
  }
}

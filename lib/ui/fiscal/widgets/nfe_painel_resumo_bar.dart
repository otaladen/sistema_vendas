import 'package:flutter/material.dart';

import '../../../domain/fiscal/nfe_painel_resumo.dart';

/// Chips de KPI do painel NF-e.
class NfePainelResumoBar extends StatelessWidget {
  const NfePainelResumoBar({super.key, required this.resumo});

  final NfePainelResumo resumo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _chip(
            theme,
            label: 'Sem NF-e',
            valor: resumo.vendasSemNfeAutorizada,
            icon: Icons.pending_actions_outlined,
            cor: resumo.vendasSemNfeAutorizada > 0
                ? theme.colorScheme.tertiary
                : null,
          ),
          _chip(
            theme,
            label: 'Processando',
            valor: resumo.processando,
            icon: Icons.hourglass_top_outlined,
            cor: resumo.processando > 0 ? theme.colorScheme.primary : null,
          ),
          _chip(
            theme,
            label: 'Rejeitadas',
            valor: resumo.rejeitadas,
            icon: Icons.error_outline,
            cor: resumo.rejeitadas > 0 ? theme.colorScheme.error : null,
          ),
          _chip(
            theme,
            label: 'Autorizadas',
            valor: resumo.autorizadas,
            icon: Icons.check_circle_outline,
            cor: Colors.green.shade700,
          ),
          _chip(
            theme,
            label: 'Canceladas',
            valor: resumo.canceladas,
            icon: Icons.cancel_outlined,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    ThemeData theme, {
    required String label,
    required int valor,
    required IconData icon,
    Color? cor,
  }) {
    return Chip(
      avatar: Icon(icon, size: 18, color: cor ?? theme.colorScheme.onSurfaceVariant),
      label: Text('$label: $valor'),
      visualDensity: VisualDensity.compact,
    );
  }
}

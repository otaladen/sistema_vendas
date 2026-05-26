import 'package:flutter/material.dart';

import '../../../domain/fiscal/nfe_pre_emissao_service.dart';

/// Checklist pre-emissao NF-e (bloqueios e avisos).
class NfeChecklistPanel extends StatelessWidget {
  const NfeChecklistPanel({
    super.key,
    required this.resultado,
    required this.podeEmitir,
  });

  final NfePreEmissaoResultado resultado;
  final bool podeEmitir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloqueios = resultado.totalBloqueios;
    final avisos = resultado.totalAvisos;

    Color corStatus;
    String rotuloStatus;
    IconData iconeStatus;
    if (!podeEmitir) {
      corStatus = theme.colorScheme.error;
      rotuloStatus = bloqueios == 1
          ? '1 pendencia bloqueante'
          : '$bloqueios pendencias bloqueantes';
      iconeStatus = Icons.block;
    } else if (avisos > 0) {
      corStatus = Colors.orange.shade800;
      rotuloStatus = 'Pronto com $avisos aviso(s)';
      iconeStatus = Icons.warning_amber_outlined;
    } else {
      corStatus = Colors.green.shade700;
      rotuloStatus = 'Pronto para emitir';
      iconeStatus = Icons.check_circle_outline;
    }

    return Card(
      elevation: 0,
      color: corStatus.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(iconeStatus, color: corStatus),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Checklist pre-emissao',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    rotuloStatus,
                    style: TextStyle(
                      color: corStatus,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: corStatus.withValues(alpha: 0.12),
                  side: BorderSide(color: corStatus.withValues(alpha: 0.35)),
                ),
              ],
            ),
            if (resultado.interestadual) ...[
              const SizedBox(height: 8),
              Text(
                'Destino: ${resultado.ufDestinatario} · '
                '${resultado.consumidorFinal ? "Consumidor final" : "Contribuinte"}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            ...resultado.checklist.map((c) => _linhaChecklist(theme, c)),
          ],
        ),
      ),
    );
  }

  Widget _linhaChecklist(ThemeData theme, NfeChecklistItem item) {
    final (icone, cor) = switch (item.severidade) {
      NfeChecklistSeveridade.ok => (
          Icons.check_circle_outline,
          Colors.green.shade700,
        ),
      NfeChecklistSeveridade.aviso => (
          Icons.warning_amber_outlined,
          Colors.orange.shade800,
        ),
      NfeChecklistSeveridade.bloqueio => (
          Icons.cancel_outlined,
          theme.colorScheme.error,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.titulo, style: theme.textTheme.bodyMedium),
                if (item.detalhe != null && item.detalhe!.isNotEmpty)
                  Text(
                    item.detalhe!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../services/fiscal_config_store.dart';

/// Alerta de ambiente Focus (homologacao vs producao).
class NfeAmbienteBanner extends StatelessWidget {
  const NfeAmbienteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homolog = FiscalConfigStore.efetivo.homologacao;
    if (!homolog) {
      return Material(
        color: Colors.green.shade50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.verified_outlined, color: Colors.green.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ambiente PRODUCAO — notas com validade juridica.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: theme.colorScheme.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'HOMOLOGACAO — notas de teste, sem validade fiscal. '
                'Cancelamento e CC-e so para conferencia.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

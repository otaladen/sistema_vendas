import 'package:flutter/material.dart';

/// Empty state contextual para listas de consulta (PDV, estoque, etc.).
class ConsultaListaVazia extends StatelessWidget {
  const ConsultaListaVazia({
    super.key,
    required this.mensagem,
    this.dica,
    this.icone = Icons.search_off_outlined,
  });

  final String mensagem;
  final String? dica;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icone,
              size: 52,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (dica != null && dica!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                dica!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

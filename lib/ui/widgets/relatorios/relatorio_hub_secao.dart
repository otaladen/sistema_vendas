import 'package:flutter/material.dart';

/// Cabecalho de secao no hub de relatorios.
class RelatorioHubSecao extends StatelessWidget {
  const RelatorioHubSecao({
    super.key,
    required this.titulo,
    required this.icone,
    this.quantidadeItens,
  });

  final String titulo;
  final IconData icone;
  final int? quantidadeItens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icone, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (quantidadeItens != null)
            Text(
              '$quantidadeItens',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_semantic_helper.dart';
import 'estoque_layout.dart';

/// Faixa compacta de alertas operacionais do estoque.
class EstoqueAlertaStrip extends StatelessWidget {
  const EstoqueAlertaStrip({
    super.key,
    required this.criticosDiagnostico,
    required this.alertasDiagnostico,
    required this.qtdCriticosPp,
    this.onVerDiagnostico,
    this.onFiltrarPp,
    this.onListaCompra,
    this.onDismiss,
  });

  final int criticosDiagnostico;
  final int alertasDiagnostico;
  final int qtdCriticosPp;
  final VoidCallback? onVerDiagnostico;
  final VoidCallback? onFiltrarPp;
  final VoidCallback? onListaCompra;
  final VoidCallback? onDismiss;

  bool get _temDiagnostico => criticosDiagnostico > 0 || alertasDiagnostico > 0;
  bool get _temPp => qtdCriticosPp > 0;

  @override
  Widget build(BuildContext context) {
    if (!_temDiagnostico && !_temPp) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final scheme = theme.colorScheme;
    final compact = EstoqueLayout.isCompact(context);
    final severo = criticosDiagnostico > 0;
    final fg = severo ? semantic.errorFg : semantic.warningFg;
    final bg = severo ? semantic.errorBg : semantic.warningBg;
    final border = severo ? semantic.errorBorder : semantic.warningBorder;

    final partes = <String>[];
    if (_temDiagnostico) {
      partes.add(
        compact
            ? '$criticosDiagnostico crit. · $alertasDiagnostico alerta(s)'
            : '$criticosDiagnostico critico(s) e $alertasDiagnostico alerta(s) no estoque',
      );
    }
    if (_temPp) {
      partes.add(
        compact
            ? '$qtdCriticosPp no PP'
            : '$qtdCriticosPp produto(s) no ou abaixo do PP',
      );
    }

    final acoes = <Widget>[
      if (_temDiagnostico && onVerDiagnostico != null)
        compact
            ? IconButton(
                tooltip: 'Diagnostico',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onVerDiagnostico,
                icon: Icon(Icons.health_and_safety_outlined, color: fg),
              )
            : TextButton(
                onPressed: onVerDiagnostico,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Diagnostico'),
              ),
      if (_temPp && onFiltrarPp != null)
        compact
            ? IconButton(
                tooltip: 'Filtrar PP',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onFiltrarPp,
                icon: Icon(Icons.filter_alt_outlined, color: fg),
              )
            : TextButton(
                onPressed: onFiltrarPp,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Filtrar PP'),
              ),
      if (_temPp && onListaCompra != null)
        compact
            ? IconButton(
                tooltip: 'Lista de compras',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onListaCompra,
                icon: Icon(Icons.playlist_add_check_outlined, color: fg),
              )
            : TextButton(
                onPressed: onListaCompra,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Compras'),
              ),
      if (onDismiss != null)
        IconButton(
          tooltip: 'Ocultar alertas',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: onDismiss,
          icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
        ),
    ];

    return Material(
      color: bg.withValues(alpha: 0.55),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: border.withValues(alpha: 0.65)),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 6,
          ),
          child: Row(
            children: [
              Icon(
                severo
                    ? Icons.health_and_safety_outlined
                    : Icons.shopping_bag_outlined,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  partes.join(' · '),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 12 : null,
                  ),
                ),
              ),
              ...acoes,
            ],
          ),
        ),
      ),
    );
  }
}

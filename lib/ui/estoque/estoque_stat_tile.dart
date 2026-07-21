import 'package:flutter/material.dart';

/// KPI compacto e neutro para a tela de Estoque.
class EstoqueStatTile extends StatelessWidget {
  const EstoqueStatTile({
    super.key,
    required this.icon,
    required this.titulo,
    required this.valor,
    this.onTap,
    this.destaqueCor,
    this.faixaCompacta = false,
  });

  final IconData icon;
  final String titulo;
  final String valor;
  final VoidCallback? onTap;
  final Color? destaqueCor;

  /// Modo faixa horizontal (celular / tablet estreito).
  final bool faixaCompacta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = destaqueCor ?? scheme.primary;

    final conteudo = Container(
      width: faixaCompacta ? 132 : double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: faixaCompacta ? 10 : 14,
        vertical: faixaCompacta ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: faixaCompacta ? 18 : 20,
            color: accent.withValues(alpha: 0.9),
          ),
          SizedBox(width: faixaCompacta ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: faixaCompacta ? 10 : null,
                  ),
                ),
                SizedBox(height: faixaCompacta ? 1 : 2),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (faixaCompacta
                          ? theme.textTheme.labelLarge
                          : theme.textTheme.titleSmall)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return conteudo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: scheme.primary.withValues(alpha: 0.06),
        child: conteudo,
      ),
    );
  }
}

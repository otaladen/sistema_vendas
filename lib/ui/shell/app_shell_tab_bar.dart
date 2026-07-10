import 'package:flutter/material.dart';

import 'app_shell_tab.dart';

/// Barra de abas do shell (estilo ERP: varias telas abertas, fecha manualmente).
class AppShellTabBar extends StatelessWidget {
  const AppShellTabBar({
    super.key,
    required this.tabs,
    required this.indiceAtivo,
    required this.onSelecionar,
    required this.onFecharAtiva,
  });

  final List<AppShellTab> tabs;
  final int indiceAtivo;
  final ValueChanged<int> onSelecionar;
  final VoidCallback onFecharAtiva;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final podeFechar = tabs.length > 1;

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: tabs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final ativo = index == indiceAtivo;
                    return _AbaChip(
                      titulo: tab.titulo,
                      ativo: ativo,
                      onTap: () => onSelecionar(index),
                    );
                  },
                ),
              ),
              if (podeFechar)
                Tooltip(
                  message: 'Fechar aba',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    iconSize: 18,
                    onPressed: onFecharAtiva,
                    icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbaChip extends StatelessWidget {
  const _AbaChip({
    required this.titulo,
    required this.ativo,
    required this.onTap,
  });

  final String titulo;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = ativo
        ? scheme.surface
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final border = ativo
        ? scheme.primary.withValues(alpha: 0.45)
        : scheme.outlineVariant.withValues(alpha: 0.35);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                    color: ativo ? scheme.primary : scheme.onSurface,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

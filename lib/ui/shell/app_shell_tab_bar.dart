import 'package:flutter/material.dart';

import 'app_shell_tab.dart';

/// Barra de abas do shell (estilo ERP: singleton de modulo + documentos).
///
/// O X fica no canto direito (fecha a aba ativa), longe do clique de selecao.
class AppShellTabBar extends StatelessWidget {
  const AppShellTabBar({
    super.key,
    required this.tabs,
    required this.indiceAtivo,
    required this.onSelecionar,
    required this.onFechar,
    required this.onFecharOutras,
    required this.onFecharTodas,
    this.trailing,
  });

  final List<AppShellTab> tabs;
  final int indiceAtivo;
  final ValueChanged<int> onSelecionar;
  final ValueChanged<int> onFechar;
  final ValueChanged<int> onFecharOutras;
  final VoidCallback onFecharTodas;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final podeFecharAlguma = tabs.length > 1;

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: tabs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 4),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final ativo = index == indiceAtivo;
                    return _AbaChip(
                      titulo: tab.titulo,
                      ativo: ativo,
                      podeFechar: podeFecharAlguma,
                      onTap: () => onSelecionar(index),
                      onFechar: () => onFechar(index),
                      onFecharOutras: () => onFecharOutras(index),
                      onFecharTodas: onFecharTodas,
                    );
                  },
                ),
              ),
              if (trailing != null) ...[
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                trailing!,
              ],
              if (podeFecharAlguma) ...[
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    tooltip: 'Fechar aba atual (Ctrl+W)',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    iconSize: 18,
                    onPressed: () => onFechar(indiceAtivo),
                    icon: Icon(
                      Icons.close,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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
    required this.podeFechar,
    required this.onTap,
    required this.onFechar,
    required this.onFecharOutras,
    required this.onFecharTodas,
  });

  final String titulo;
  final bool ativo;
  final bool podeFechar;
  final VoidCallback onTap;
  final VoidCallback onFechar;
  final VoidCallback onFecharOutras;
  final VoidCallback onFecharTodas;

  Future<void> _mostrarMenuContexto(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'fechar',
          enabled: podeFechar,
          child: const Text('Fechar aba'),
        ),
        PopupMenuItem(
          value: 'outras',
          enabled: podeFechar,
          child: const Text('Fechar outras'),
        ),
        PopupMenuItem(
          value: 'todas',
          enabled: podeFechar,
          child: const Text('Fechar todas'),
        ),
      ],
    );
    switch (selected) {
      case 'fechar':
        onFechar();
      case 'outras':
        onFecharOutras();
      case 'todas':
        onFecharTodas();
    }
  }

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
        onSecondaryTapDown: (details) =>
            _mostrarMenuContexto(context, details.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final pos =
              box.localToGlobal(Offset(box.size.width / 2, box.size.height));
          _mostrarMenuContexto(context, pos);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
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

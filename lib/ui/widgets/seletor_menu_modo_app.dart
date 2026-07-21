import 'package:flutter/material.dart';

import '../theme/app_menu_modo_id.dart';
import '../theme/app_menu_modo_scope.dart';
import 'seletor_tema_app.dart';

/// Botao para alternar o estilo visual do menu principal.
class SeletorMenuModoApp extends StatelessWidget {
  const SeletorMenuModoApp({super.key, this.compacto = false});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scope = AppMenuModoScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final atual = scope.modoAtual;
    final compacta = SeletorTemaApp.uiCompacta(context);

    if (compacta) {
      return IconButton(
        tooltip: 'Modo do menu (${atual.rotulo})',
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
        onPressed: () => _escolherEAplicar(context, scope),
        icon: Icon(
          atual.icone,
          size: 22,
          color: tema.colorScheme.onSurface,
        ),
      );
    }

    return PopupMenuButton<AppMenuModoId>(
      tooltip: 'Modo do menu lateral',
      initialValue: atual,
      onSelected: (valor) => scope.definirModo(valor),
      itemBuilder: (ctx) => [
        for (final opcao in AppMenuModoId.values)
          PopupMenuItem<AppMenuModoId>(
            value: opcao,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  opcao.icone,
                  size: 20,
                  color: opcao == atual
                      ? tema.colorScheme.primary
                      : tema.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opcao.rotulo,
                        style: TextStyle(
                          fontWeight: opcao == atual
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        opcao.descricao,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: tema.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (opcao == atual)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: tema.colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              atual.icone,
              size: compacto ? 16 : 18,
              color: tema.colorScheme.onSurfaceVariant,
            ),
            if (!compacto) ...[
              const SizedBox(width: 6),
              Text(
                'Menu lateral',
                style: tema.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            Icon(
              Icons.arrow_drop_down_rounded,
              size: compacto ? 18 : 20,
              color: tema.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> mostrarFolha(BuildContext context) async {
    final scope = AppMenuModoScope.maybeOf(context);
    if (scope == null) return;
    await _escolherEAplicar(context, scope);
  }

  static Future<void> _escolherEAplicar(
    BuildContext context,
    AppMenuModoScope scope,
  ) async {
    final atual = scope.modoAtual;
    final escolhido = await showDialog<AppMenuModoId>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final tema = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Modo do menu'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opcao in AppMenuModoId.values)
                  ListTile(
                    leading: Icon(opcao.icone),
                    title: Text(opcao.rotulo),
                    subtitle: Text(opcao.descricao),
                    trailing: opcao == atual
                        ? Icon(
                            Icons.check_circle,
                            color: tema.colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(opcao),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
    if (escolhido == null) return;
    await scope.definirModo(escolhido);
  }
}

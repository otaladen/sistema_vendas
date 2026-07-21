import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_tema_id.dart';
import '../theme/app_tema_scope.dart';

/// Botao "Temas" com menu de paletas (estilo ERP).
class SeletorTemaApp extends StatelessWidget {
  const SeletorTemaApp({super.key, this.compacto = false});

  final bool compacto;

  /// Celular real OU largura estreita (teste / tablet fino).
  static bool uiCompacta(BuildContext context) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return true;
    return MediaQuery.sizeOf(context).width < 720;
  }

  /// Abre o seletor de temas (drawer, AppBar, rodape).
  static Future<void> mostrarFolha(BuildContext context) async {
    final scope = AppTemaScope.maybeOf(context);
    if (scope == null) return;
    await _escolherEAplicar(context, scope);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppTemaScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final atual = scope.temaAtual;
    final compacta = uiCompacta(context);

    if (compacta) {
      return IconButton(
        tooltip: 'Temas (${atual.rotulo})',
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
        onPressed: () => _escolherEAplicar(context, scope),
        icon: Badge(
          isLabelVisible: true,
          backgroundColor: atual.corDestaque,
          smallSize: 10,
          child: Icon(
            Icons.palette_outlined,
            size: 22,
            color: tema.colorScheme.onSurface,
          ),
        ),
      );
    }

    return PopupMenuButton<AppTemaId>(
      tooltip: 'Temas',
      initialValue: atual,
      onSelected: (valor) => scope.definirTema(valor),
      itemBuilder: (ctx) => [
        for (final opcao in AppTemaId.values)
          PopupMenuItem<AppTemaId>(
            value: opcao,
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: opcao.corDestaque,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tema.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(opcao.rotulo)),
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
              Icons.palette_outlined,
              size: compacto ? 16 : 18,
              color: tema.colorScheme.onSurfaceVariant,
            ),
            if (!compacto) ...[
              const SizedBox(width: 6),
              Text(
                'Temas',
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

  static Future<void> _escolherEAplicar(
    BuildContext context,
    AppTemaScope scope,
  ) async {
    final atual = scope.temaAtual;
    final escolhido = await showDialog<AppTemaId>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final tema = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Temas'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opcao in AppTemaId.values)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: opcao.corDestaque,
                      radius: 14,
                    ),
                    title: Text(opcao.rotulo),
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
    await scope.definirTema(escolhido);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Tema: ${escolhido.rotulo}'),
      ),
    );
  }
}

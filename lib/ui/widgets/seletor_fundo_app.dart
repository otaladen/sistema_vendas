import 'package:flutter/material.dart';

import '../theme/app_fundo_camada.dart';
import '../theme/app_fundo_id.dart';
import '../theme/app_fundo_scope.dart';
import 'seletor_tema_app.dart';

/// Botao "Fundo" com estilos pintados (sem foto de wallpaper).
class SeletorFundoApp extends StatelessWidget {
  const SeletorFundoApp({super.key, this.compacto = false});

  final bool compacto;

  static Future<void> mostrarFolha(BuildContext context) async {
    final scope = AppFundoScope.maybeOf(context);
    if (scope == null) return;
    await _escolherEAplicar(context, scope);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppFundoScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final atual = scope.fundoAtual;
    final compacta = SeletorTemaApp.uiCompacta(context);

    if (compacta) {
      return IconButton(
        tooltip: 'Plano de fundo (${atual.rotulo})',
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

    return PopupMenuButton<AppFundoId>(
      tooltip: 'Plano de fundo',
      initialValue: atual,
      onSelected: (valor) => scope.definirFundo(valor),
      itemBuilder: (ctx) => [
        for (final opcao in AppFundoId.values)
          PopupMenuItem<AppFundoId>(
            value: opcao,
            child: Row(
              children: [
                _FundoMiniatura(estilo: opcao, largura: 44, altura: 28),
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
                'Fundo',
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
    AppFundoScope scope,
  ) async {
    final atual = scope.fundoAtual;
    final escolhido = await showDialog<AppFundoId>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final tema = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Plano de fundo'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Estilos desenhados pelo sistema, sem foto. '
                    'Listas e PDV continuam legiveis.',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final opcao in AppFundoId.values)
                  ListTile(
                    leading: _FundoMiniatura(estilo: opcao),
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
    await scope.definirFundo(escolhido);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Fundo: ${escolhido.rotulo}'),
      ),
    );
  }
}

class _FundoMiniatura extends StatelessWidget {
  const _FundoMiniatura({
    required this.estilo,
    this.largura = 56,
    this.altura = 36,
  });

  final AppFundoId estilo;
  final double largura;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: largura,
          height: altura,
          child: CustomPaint(
            painter: AppFundoPainter(estilo: estilo, scheme: scheme),
          ),
        ),
      ),
    );
  }
}

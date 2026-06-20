import 'package:flutter/material.dart';

import '../theme/app_tema_id.dart';
import '../theme/app_tema_scope.dart';

/// Botao "Temas" com menu de paletas (como no ERP legado).
class SeletorTemaApp extends StatelessWidget {
  const SeletorTemaApp({super.key, this.compacto = false});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scope = AppTemaScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final atual = scope.temaAtual;

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
}

import 'package:flutter/material.dart';

import '../../domain/usuario_resumo_permissoes.dart';
import 'usuario_form_state.dart';

class UsuariosResumoPanel extends StatelessWidget {
  const UsuariosResumoPanel({super.key, required this.form});

  final UsuarioFormState form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resumo = UsuarioResumoPermissoes.gerar(form.usuario);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'O que este usuario pode fazer',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (resumo.pode.isNotEmpty) ...[
              Text('Pode', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              ...resumo.pode.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(t, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              ),
            ],
            if (resumo.naoPode.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nao pode', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              ...resumo.naoPode.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(t, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

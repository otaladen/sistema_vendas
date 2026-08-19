import 'package:flutter/material.dart';

import '../../theme/app_semantic_helper.dart';

/// Rodape fixo de acoes do cadastro de usuarios (mesmo visual de clientes).
class UsuarioCadastroRodape extends StatelessWidget {
  const UsuarioCadastroRodape({
    super.key,
    required this.emEdicao,
    required this.onSalvar,
    required this.onNovo,
    this.onExcluir,
    this.podeExcluir = false,
    this.extraActions = const [],
  });

  final bool emEdicao;
  final VoidCallback onSalvar;
  final VoidCallback onNovo;
  final VoidCallback? onExcluir;
  final bool podeExcluir;
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final corSalvar = context.semanticColors.successFg;
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onSalvar,
              style: FilledButton.styleFrom(
                backgroundColor: corSalvar,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.save_outlined, size: 20),
              label: Text(emEdicao ? 'Salvar (F5)' : 'Salvar usuario (F5)'),
            ),
            OutlinedButton.icon(
              onPressed: onNovo,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.45),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Novo'),
            ),
            ...extraActions,
            if (podeExcluir && onExcluir != null)
              OutlinedButton.icon(
                onPressed: onExcluir,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  'Excluir',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

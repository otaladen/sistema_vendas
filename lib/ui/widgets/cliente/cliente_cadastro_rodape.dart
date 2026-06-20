import 'package:flutter/material.dart';

import '../../theme/app_semantic_helper.dart';

/// Rodape fixo de acoes do cadastro de clientes.
class ClienteCadastroRodape extends StatelessWidget {
  const ClienteCadastroRodape({
    super.key,
    required this.emEdicao,
    required this.onSalvar,
    required this.onNovo,
    required this.onLimpar,
    this.onExcluir,
    this.podeExcluir = false,
  });

  final bool emEdicao;
  final VoidCallback onSalvar;
  final VoidCallback onNovo;
  final VoidCallback onLimpar;
  final VoidCallback? onExcluir;
  final bool podeExcluir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final corSalvar = context.semanticColors.successFg;
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onSalvar,
              style: FilledButton.styleFrom(
                backgroundColor: corSalvar,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.save_outlined, size: 20),
              label: Text(emEdicao ? 'Salvar (F5)' : 'Salvar cliente (F5)'),
            ),
            OutlinedButton.icon(
              onPressed: onNovo,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Novo'),
            ),
            if (podeExcluir && onExcluir != null)
              OutlinedButton.icon(
                onPressed: onExcluir,
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
            OutlinedButton.icon(
              onPressed: onLimpar,
              icon: Icon(
                emEdicao ? Icons.close : Icons.cleaning_services_outlined,
                size: 18,
              ),
              label: Text(emEdicao ? 'Cancelar (Esc)' : 'Limpar'),
            ),
          ],
        ),
      ),
    );
  }
}

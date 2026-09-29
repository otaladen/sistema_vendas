import 'package:flutter/material.dart';

/// Barra fixa no rodape da secao: sem ela o botao de salvar rola com o conteudo
/// e nada avisa que existem alteracoes pendentes.
class ConfigBarraSalvar extends StatelessWidget {
  const ConfigBarraSalvar({
    super.key,
    required this.pendencias,
    required this.salvando,
    required this.onSalvar,
    required this.onDescartar,
  });

  /// Quantos cartoes da secao foram mexidos e ainda nao foram gravados.
  final int pendencias;

  final bool salvando;
  final VoidCallback onSalvar;
  final VoidCallback onDescartar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: pendencias == 0
          ? const SizedBox(width: double.infinity)
          : Material(
              color: scheme.surfaceContainerHigh,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(height: 1, color: scheme.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note_outlined,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            pendencias == 1
                                ? '1 bloco com alterações não salvas'
                                : '$pendencias blocos com alterações não salvas',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: salvando ? null : onDescartar,
                          child: const Text('Descartar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: salvando ? null : onSalvar,
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            salvando ? 'Salvando...' : 'Salvar tudo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

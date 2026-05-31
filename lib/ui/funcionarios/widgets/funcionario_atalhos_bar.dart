import 'package:flutter/material.dart';

/// Barra de atalhos e navegacao rapida entre registros.
class FuncionarioAtalhosBar extends StatelessWidget {
  const FuncionarioAtalhosBar({
    super.key,
    required this.onPrimeiro,
    required this.onAnterior,
    required this.onProximo,
    required this.onUltimo,
    required this.onPesquisar,
    required this.onNovo,
    this.mostrarNavegacao = true,
    this.compact = false,
  });

  final VoidCallback onPrimeiro;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;
  final VoidCallback onUltimo;
  final VoidCallback onPesquisar;
  final VoidCallback onNovo;
  final bool mostrarNavegacao;
  final bool compact;

  static ButtonStyle get _contorno => OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (mostrarNavegacao) ...[
            OutlinedButton(style: _contorno, onPressed: onPrimeiro, child: const Text('|<')),
            OutlinedButton(style: _contorno, onPressed: onAnterior, child: const Text('<')),
            OutlinedButton(style: _contorno, onPressed: onProximo, child: const Text('>')),
            OutlinedButton(style: _contorno, onPressed: onUltimo, child: const Text('>|')),
            Container(
              width: 1,
              height: 24,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ],
          OutlinedButton.icon(
            style: _contorno,
            onPressed: onPesquisar,
            icon: const Icon(Icons.manage_search, size: 16),
            label: const Text('F3 · Lista'),
          ),
          OutlinedButton.icon(
            style: _contorno,
            onPressed: onNovo,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Esc · Novo'),
          ),
          Text(
            'F5 / F10 salvar',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

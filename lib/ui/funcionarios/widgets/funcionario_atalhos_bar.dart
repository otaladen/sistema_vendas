import 'package:flutter/material.dart';

/// Barra enxuta de pesquisa e navegacao entre registros (estilo cadastro produtos).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final pesquisar = Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 10 : 12,
          ),
        ),
        onPressed: onPesquisar,
        icon: const Icon(Icons.search, size: 20),
        label: const Text('Pesquisar funcionario'),
      ),
    );

    final novo = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 10 : 12,
        ),
      ),
      onPressed: onNovo,
      icon: const Icon(Icons.add, size: 20),
      label: Text(compact ? 'Novo' : 'Novo (Esc)'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            pesquisar,
            const SizedBox(width: 8),
            novo,
          ],
        ),
        if (mostrarNavegacao) ...[
          SizedBox(height: compact ? 4 : 6),
          Row(
            children: [
              IconButton(
                tooltip: 'Primeiro',
                onPressed: onPrimeiro,
                icon: const Icon(Icons.first_page_outlined),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Anterior',
                onPressed: onAnterior,
                icon: const Icon(Icons.navigate_before_outlined),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Proximo',
                onPressed: onProximo,
                icon: const Icon(Icons.navigate_next_outlined),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Ultimo',
                onPressed: onUltimo,
                icon: const Icon(Icons.last_page_outlined),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text(
                'F5 / F10 salvar',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

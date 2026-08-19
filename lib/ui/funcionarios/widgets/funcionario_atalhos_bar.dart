import 'package:flutter/material.dart';

/// Barra de pesquisa e navegacao (mesmo padrao do cadastro de clientes).
class FuncionarioAtalhosBar extends StatelessWidget {
  const FuncionarioAtalhosBar({
    super.key,
    required this.onPrimeiro,
    required this.onAnterior,
    required this.onProximo,
    required this.onUltimo,
    required this.onPesquisar,
    this.onNovo,
    this.mostrarNavegacao = true,
    this.compact = false,
  });

  final VoidCallback onPrimeiro;
  final VoidCallback onAnterior;
  final VoidCallback onProximo;
  final VoidCallback onUltimo;
  final VoidCallback onPesquisar;
  final VoidCallback? onNovo;
  final bool mostrarNavegacao;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pesquisaBtn = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 12,
        ),
      ),
      onPressed: onPesquisar,
      icon: const Icon(Icons.search, size: 20),
      label: const Text('Pesquisar funcionario'),
    );

    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Primeiro',
          onPressed: onPrimeiro,
          icon: const Icon(Icons.first_page_outlined),
        ),
        IconButton(
          tooltip: 'Anterior',
          onPressed: onAnterior,
          icon: const Icon(Icons.navigate_before_outlined),
        ),
        IconButton(
          tooltip: 'Proximo',
          onPressed: onProximo,
          icon: const Icon(Icons.navigate_next_outlined),
        ),
        IconButton(
          tooltip: 'Ultimo',
          onPressed: onUltimo,
          icon: const Icon(Icons.last_page_outlined),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pesquisaBtn,
          if (mostrarNavegacao) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [nav],
            ),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: pesquisaBtn),
        if (mostrarNavegacao) nav,
      ],
    );
  }
}

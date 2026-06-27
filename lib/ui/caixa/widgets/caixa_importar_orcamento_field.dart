import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campo rapido: numero do orcamento + Enter para importar no caixa.
class CaixaImportarOrcamentoField extends StatelessWidget {
  const CaixaImportarOrcamentoField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.habilitado,
    required this.onImportar,
    this.onAbrirPesquisa,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool habilitado;
  final ValueChanged<int> onImportar;
  final VoidCallback? onAbrirPesquisa;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: habilitado,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Numero do orcamento',
                  hintText: 'Digite e pressione Enter',
                  prefixIcon: const Icon(Icons.tag_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Pesquisa avancada (F1)',
                    onPressed: habilitado ? onAbrirPesquisa : null,
                    icon: const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (_) => _submeter(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: habilitado ? _submeter : null,
              icon: const Icon(Icons.download_outlined, size: 20),
              label: const Text('Importar'),
            ),
          ],
        ),
      ),
    );
  }

  void _submeter() {
    final n = int.tryParse(controller.text.trim()) ?? 0;
    if (n <= 0) return;
    onImportar(n);
  }
}

import 'package:flutter/material.dart';

/// Campo de busca global na barra principal da aba Entregas.
class EntregasCampoBuscaGlobal extends StatelessWidget {
  const EntregasCampoBuscaGlobal({
    super.key,
    required this.controller,
    required this.onChanged,
    this.compacto = false,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buscaAtiva = controller.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: compacto ? 4 : 6),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Controle / # pedido / cliente / bairro',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: buscaAtiva
              ? IconButton(
                  tooltip: 'Limpar busca',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

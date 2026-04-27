import 'dart:io';

import 'package:flutter/material.dart';

import '../model/produto.dart';

class ProdutoDetalheVendaPage extends StatelessWidget {
  const ProdutoDetalheVendaPage({super.key, required this.produto});

  final Produto produto;

  Future<void> _abrirZoomFoto(BuildContext context) async {
    if (produto.fotoPath.trim().isEmpty) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.file(
                      File(produto.fotoPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Produto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              produto.nome,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('SKU: ${produto.codigoInterno}'),
            if (produto.fotoPath.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _abrirZoomFoto(context),
                icon: const Icon(Icons.zoom_in),
                label: const Text('Ampliar foto'),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              width: double.infinity,
              child: produto.fotoPath.trim().isEmpty
                  ? Container(
                      alignment: Alignment.center,
                      color: Colors.grey.shade100,
                      child: const Text('Produto sem foto cadastrada.'),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.grey.shade100,
                        child: Image.file(
                          File(produto.fotoPath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              alignment: Alignment.center,
                              color: Colors.grey.shade100,
                              child: const Text('Nao foi possivel carregar a foto.'),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              'Descricao tecnica',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    produto.descricao.trim().isEmpty
                        ? 'Sem descricao tecnica cadastrada.'
                        : produto.descricao,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../model/produto.dart';

/// Modal compacto com foto e descricao (PDV e demais telas de venda).
Future<void> mostrarModalDetalheProdutoVenda(
  BuildContext context, {
  required Produto produto,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final alturaMax = MediaQuery.sizeOf(dialogContext).height * 0.72;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: alturaMax.clamp(320.0, 640.0),
          ),
          child: ProdutoDetalheVendaConteudo(produto: produto),
        ),
      );
    },
  );
}

/// Conteudo do modal de detalhe do produto na venda.
class ProdutoDetalheVendaConteudo extends StatelessWidget {
  const ProdutoDetalheVendaConteudo({super.key, required this.produto});

  final Produto produto;

  Future<void> _abrirZoomFoto(BuildContext context) async {
    if (produto.fotoPath.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(ctx).width * 0.85,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(ctx),
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
        ),
      ),
    );
  }

  Widget _buildFoto(BuildContext context, {required double altura}) {
    final scheme = Theme.of(context).colorScheme;
    final semFoto = produto.fotoPath.trim().isEmpty;
    final foto = semFoto
        ? Container(
            height: altura,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Sem foto',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => _abrirZoomFoto(context),
                child: SizedBox(
                  height: altura,
                  width: double.infinity,
                  child: Image.file(
                    File(produto.fotoPath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        'Foto indisponivel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        foto,
        if (!semFoto)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Toque na foto para ampliar',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildDescricao(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desc = produto.descricao.trim().isEmpty
        ? 'Sem descricao tecnica cadastrada.'
        : produto.descricao.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Descricao tecnica',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(desc),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'SKU: ${produto.codigoInterno}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ladoALado = constraints.maxWidth >= 420;
                if (ladoALado) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 200,
                        child: _buildFoto(context, altura: 200),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: _buildDescricao(context)),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFoto(context, altura: 160),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _buildDescricao(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pagina cheia legada; prefira [mostrarModalDetalheProdutoVenda].
@Deprecated('Use mostrarModalDetalheProdutoVenda para nao ocupar a tela inteira.')
class ProdutoDetalheVendaPage extends StatelessWidget {
  const ProdutoDetalheVendaPage({super.key, required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do Produto')),
      body: ProdutoDetalheVendaConteudo(produto: produto),
    );
  }
}

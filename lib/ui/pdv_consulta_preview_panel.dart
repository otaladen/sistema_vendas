import 'dart:io';

import 'package:flutter/material.dart';

import '../model/produto.dart';

/// Painel lateral (ou compacto) com foto e resumo do item selecionado na consulta PDV.
class PdvConsultaPreviewPanel extends StatelessWidget {
  const PdvConsultaPreviewPanel({
    super.key,
    required this.produto,
    required this.precoFormatado,
    required this.rotuloPreco,
    required this.estoqueCritico,
    required this.onDetalhes,
    this.compacto = false,
  });

  final Produto produto;
  final String precoFormatado;
  final String rotuloPreco;
  final bool estoqueCritico;
  final VoidCallback onDetalhes;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alturaFoto = compacto ? 140.0 : 200.0;

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: compacto
                ? BorderSide.none
                : BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
            bottom: compacto
                ? BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  )
                : BorderSide.none,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(compacto ? 12 : 14, 12, compacto ? 12 : 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Selecionado',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              _FotoPreview(
                key: ValueKey<int>(produto.id),
                fotoPath: produto.fotoPath,
                altura: alturaFoto,
              ),
              const SizedBox(height: 10),
              Text(
                produto.nome,
                maxLines: compacto ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              if (produto.codigoInterno.trim().isNotEmpty)
                Text(
                  'SKU: ${produto.codigoInterno}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              if (produto.codigoBarras.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'EAN: ${produto.codigoBarras}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                precoFormatado,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
              ),
              Text(
                rotuloPreco,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Livre: ${produto.estoqueLivreParaVenda} · '
                'Fis: ${produto.estoqueReal} · '
                'Res: ${produto.estoqueReservado}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: estoqueCritico ? scheme.error : scheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onDetalhes,
                icon: const Icon(Icons.info_outline, size: 20),
                label: const Text('Detalhes (Espaco / F9)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FotoPreview extends StatelessWidget {
  const _FotoPreview({
    super.key,
    required this.fotoPath,
    required this.altura,
  });

  final String fotoPath;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = fotoPath.trim();

    if (path.isEmpty) {
      return _placeholder(
        context,
        scheme,
        child: Text(
          'Sem foto',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: altura,
        width: double.infinity,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => _placeholder(
            context,
            scheme,
            child: Text(
              'Foto indisponivel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context,
    ColorScheme scheme, {
    required Widget child,
  }) {
    return Container(
      height: altura,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}

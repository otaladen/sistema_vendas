import 'dart:io';

import 'package:flutter/material.dart';

import '../model/produto.dart';
import 'produto_detalhe_venda_page.dart';

/// Tres listas de preco do produto (ativo em destaque).
class PdvConsultaTresPrecos extends StatelessWidget {
  const PdvConsultaTresPrecos({
    super.key,
    required this.produto,
    required this.precoListaAtivo,
    required this.precoUnitarioDe,
    required this.rotuloPreco,
    required this.formatarMoeda,
    this.compacto = false,
  });

  static const _tiposPreco = ['preco1', 'preco2', 'preco3'];

  final Produto produto;
  final String precoListaAtivo;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final String Function(String precoTipo) rotuloPreco;
  final String Function(double) formatarMoeda;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _tiposPreco.length; i++) ...[
          if (i > 0) SizedBox(height: compacto ? 4 : 6),
          _linhaPreco(context, scheme, _tiposPreco[i]),
        ],
      ],
    );
  }

  Widget _linhaPreco(BuildContext context, ColorScheme scheme, String tipo) {
    final ativo = tipo == precoListaAtivo;
    final valor = precoUnitarioDe(produto, tipo);
    final rotulo = rotuloPreco(tipo);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ativo
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ativo ? 8 : 4,
          vertical: ativo ? 6 : 2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: compacto ? 72 : 80,
              child: Text(
                rotulo,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: ativo ? FontWeight.w700 : FontWeight.w500,
                      color: ativo ? scheme.primary : scheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                formatarMoeda(valor),
                textAlign: TextAlign.end,
                style: (ativo
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                  fontWeight: ativo ? FontWeight.bold : FontWeight.w600,
                  color: ativo ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (ativo) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle, size: 16, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Painel lateral (ou compacto) com foto e resumo do item selecionado na consulta PDV.
class PdvConsultaPreviewPanel extends StatelessWidget {
  const PdvConsultaPreviewPanel({
    super.key,
    required this.produto,
    required this.precoListaAtivo,
    required this.precoUnitarioDe,
    required this.rotuloPreco,
    required this.formatarMoeda,
    required this.estoqueCritico,
    required this.onDetalhes,
    this.compacto = false,
    this.mostrarDescricaoInline = false,
    this.tituloPainel = 'Selecionado',
  });

  final Produto produto;
  final String precoListaAtivo;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final String Function(String precoTipo) rotuloPreco;
  final String Function(double) formatarMoeda;
  final bool estoqueCritico;
  final VoidCallback onDetalhes;
  final bool compacto;
  final bool mostrarDescricaoInline;
  final String tituloPainel;

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
                tituloPainel,
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
                'Precos (F1–F3 escolhe lista ativa)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              PdvConsultaTresPrecos(
                produto: produto,
                precoListaAtivo: precoListaAtivo,
                precoUnitarioDe: precoUnitarioDe,
                rotuloPreco: rotuloPreco,
                formatarMoeda: formatarMoeda,
                compacto: compacto,
              ),
              if (produto.rotuloConversaoEmbalagem.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  produto.rotuloConversaoEmbalagem,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              if (produto.permiteQuantidadeFracionada) ...[
                const SizedBox(height: 4),
                Text(
                  'Venda fracionada permitida',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
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
              if (mostrarDescricaoInline) ...[
                const SizedBox(height: 10),
                ProdutoDescricaoTecnicaInline(
                  produto: produto,
                  alturaMaxima: compacto ? 96 : 150,
                  compacto: compacto,
                ),
              ],
              const SizedBox(height: 12),
              if (!mostrarDescricaoInline)
                FilledButton.tonalIcon(
                  onPressed: onDetalhes,
                  icon: const Icon(Icons.info_outline, size: 20),
                  label: const Text('Detalhes (Espaco / F9)'),
                )
              else
                TextButton.icon(
                  onPressed: onDetalhes,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Ampliar (Espaco / F9)'),
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

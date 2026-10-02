import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/produto_precificacao.dart';
import '../../model/produto.dart';
import '../widgets/pdv_estoque_resumo_panel.dart';
import '../widgets/produto_foto_view.dart';

/// Largura padrao do painel lateral de detalhes na gestao de produtos.
const double kDetalhesProdutoPanelLargura = 320;

final NumberFormat _moedaDetalheProduto = NumberFormat('#,##0.00', 'pt_BR');

/// Painel lateral com resumo do produto selecionado na pesquisa/gestao.
class DetalhesProdutoPanel extends StatelessWidget {
  const DetalhesProdutoPanel({
    super.key,
    required this.produto,
    required this.imagesDirectoryPath,
    required this.onFechar,
    required this.onEditar,
  });

  final Produto produto;
  final String imagesDirectoryPath;
  final VoidCallback onFechar;
  final VoidCallback onEditar;

  String _moeda(double v) => 'R\$ ${_moedaDetalheProduto.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ean = produto.codigoBarras.trim();
    final fornecedor = produto.fornecedor.trim();
    final categoria = produto.categoria.trim();
    final localizacao = produto.localizacao.trim();
    final margem = ProdutoPrecificacao.margemSobrePrecoVenda(
      custo: produto.custoMedio,
      precoVenda: produto.preco1,
    );
    final margemRuim = margem <= 0;
    final margemTxt = '${margem.toStringAsFixed(1)} %';

    return Material(
      elevation: 2,
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: kDetalhesProdutoPanelLargura,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalhes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recolher painel (Esc)',
                    onPressed: onFechar,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: produto.fotoPath.trim().isEmpty
                            ? Container(
                                width: 160,
                                height: 160,
                                color: scheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 48,
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : ProdutoFotoView(
                                fotoPath: produto.fotoPath,
                                imagesDirectoryPath: imagesDirectoryPath,
                                width: 160,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      produto.nome,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU ${produto.codigoInterno.trim().isEmpty ? '-' : produto.codigoInterno.trim()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const DetalheProdutoSecaoTitulo(
                      titulo: 'Codigo de barras (EAN)',
                    ),
                    Text(
                      ean.isEmpty ? 'Nao informado' : ean,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    const DetalheProdutoSecaoTitulo(titulo: 'Precos'),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Preco 1',
                      valor: _moeda(produto.preco1),
                    ),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Preco 2',
                      valor: _moeda(produto.preco2),
                    ),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Custo medio',
                      valor: _moeda(produto.custoMedio),
                    ),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Margem lucro',
                      valor: margemTxt,
                      valorStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                        color: margemRuim ? scheme.error : scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const DetalheProdutoSecaoTitulo(
                      titulo: 'Localizacao na loja',
                    ),
                    Text(
                      localizacao.isEmpty
                          ? 'Nao informada (corredor/gondola)'
                          : localizacao,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    const DetalheProdutoSecaoTitulo(titulo: 'Estoque'),
                    PdvEstoqueResumoPanel(produto: produto, compacto: true),
                    const SizedBox(height: 14),
                    const DetalheProdutoSecaoTitulo(
                      titulo: 'Fornecedor e categoria',
                    ),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Fornecedor',
                      valor: fornecedor.isEmpty ? '-' : fornecedor,
                    ),
                    DetalheProdutoLinhaValor(
                      rotulo: 'Categoria',
                      valor: categoria.isEmpty ? '-' : categoria,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: FilledButton.icon(
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Editar produto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetalheProdutoSecaoTitulo extends StatelessWidget {
  const DetalheProdutoSecaoTitulo({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class DetalheProdutoLinhaValor extends StatelessWidget {
  const DetalheProdutoLinhaValor({
    super.key,
    required this.rotulo,
    required this.valor,
    this.valorStyle,
  });

  final String rotulo;
  final String valor;
  final TextStyle? valorStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              rotulo,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: valorStyle ??
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

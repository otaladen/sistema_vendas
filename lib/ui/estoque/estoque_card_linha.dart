import 'package:flutter/material.dart';

import '../../domain/produto_embalagem.dart';
import '../../model/produto.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/pdv_consulta_semaforo_estoque.dart';
import 'estoque_tabela_linha.dart';

/// Card compacto de produto para telas estreitas (mobile).
class EstoqueCardLinha extends StatelessWidget {
  const EstoqueCardLinha({
    super.key,
    required this.produto,
    required this.indice,
    required this.criticoPp,
    required this.resumoLinha,
    required this.vendaFormatada,
    required this.onAcao,
    this.ppExibicao,
  });

  final Produto produto;
  final int indice;
  final bool criticoPp;
  final String resumoLinha;
  final String vendaFormatada;
  final EstoqueAcaoProduto onAcao;
  final double? ppExibicao;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final zebra = indice.isOdd
        ? scheme.surfaceContainerLowest.withValues(alpha: 0.5)
        : scheme.surface;
    final fundo = criticoPp
        ? Color.alphaBlend(
            semantic.errorBg.withValues(alpha: 0.22),
            zebra,
          )
        : zebra;

    final sku = produto.codigoInterno.trim();
    final disp = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueLivreParaVenda,
      comUnidade: true,
    );
    final fisico = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReal,
      comUnidade: false,
    );
    final reservado = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReservado,
      comUnidade: false,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: fundo,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onAcao('ajustar', produto),
          hoverColor: scheme.primary.withValues(alpha: 0.05),
          mouseCursor: SystemMouseCursors.click,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: criticoPp
                    ? semantic.errorBorder.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.65),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (criticoPp) ...[
                        Tooltip(
                          message: 'Ponto de pedido critico',
                          child: Container(
                            margin: const EdgeInsets.only(top: 2, right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: semantic.errorBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: semantic.errorBorder
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                            child: Text(
                              'PP',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: semantic.errorFg,
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: PdvConsultaSemaforoEstoque(produto: produto),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              produto.nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (sku.isNotEmpty)
                              Text(
                                sku,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 4),
                        child: Text(
                          vendaFormatada,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Acoes',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        iconSize: 22,
                        onSelected: (v) => onAcao(v, produto),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'comprar',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.playlist_add_outlined),
                              title: Text('Anotar para comprar'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'ajustar',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Ajustar estoque'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'extrato',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.receipt_long_outlined),
                              title: Text('Ver movimentacoes'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(
                        context,
                        label: 'Disp $disp',
                        destaque: produto.estoqueLivreParaVenda <=
                            produto.quantidadeMinima,
                      ),
                      _chip(context, label: 'Fis $fisico'),
                      _chip(
                        context,
                        label: 'Res $reservado',
                        destaque: produto.estoqueReservado > 0,
                      ),
                      _chip(
                        context,
                        label: 'Min ${produto.quantidadeMinima}',
                      ),
                      if (ppExibicao != null)
                        _chip(
                          context,
                          label: 'PP ${ppExibicao!.toStringAsFixed(1)}',
                          destaque: criticoPp,
                        ),
                    ],
                  ),
                  if (resumoLinha.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      resumoLinha,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    bool destaque = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: destaque
            ? semantic.warningBg.withValues(alpha: 0.55)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: destaque
              ? semantic.warningBorder.withValues(alpha: 0.7)
              : scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: destaque ? semantic.warningFg : scheme.onSurface,
        ),
      ),
    );
  }
}

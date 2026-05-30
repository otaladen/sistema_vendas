import 'package:flutter/material.dart';

import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../pdv_texto_destaque_busca.dart';
import 'pdv_estoque_resumo_panel.dart';
import 'promocao_badge.dart';

/// Linha compacta da consulta de produtos (1 linha = mais itens na tela).
class PdvConsultaLinhaProduto extends StatelessWidget {
  const PdvConsultaLinhaProduto({
    super.key,
    required this.produto,
    required this.termoBusca,
    required this.precoFormatado,
    required this.estoqueCritico,
    required this.onAdicionar,
    this.tooltipAdicionar,
    this.emPromocao = false,
    this.precoDeFormatado,
  });

  final Produto produto;
  final String termoBusca;
  final String precoFormatado;
  final bool emPromocao;
  final String? precoDeFormatado;
  final bool estoqueCritico;
  final VoidCallback onAdicionar;
  final String? tooltipAdicionar;

  static const double alturaLinha = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estiloNome =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final estiloUnidade = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSecondaryContainer,
        ) ??
        const TextStyle(fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (emPromocao) ...[
            const PromocaoBadge(compacto: true),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  pdvTextoDestaqueBusca(
                    context: context,
                    texto: produto.nome,
                    termoBusca: termoBusca,
                    estiloBase: estiloNome.copyWith(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' · ${rotuloUnidadeProdutoLista(produto)}',
                    style: estiloUnidade,
                  ),
                ],
              ),
            ),
          ),
          PdvEstoqueResumoPanel(produto: produto, compacto: true),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (precoDeFormatado != null)
                Text(
                  precoDeFormatado!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              Text(
                precoFormatado,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: emPromocao ? PromocaoBadge.corFundo : null,
                    ),
              ),
            ],
          ),
          IconButton(
            tooltip: tooltipAdicionar ?? 'Adicionar 1',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
            onPressed: onAdicionar,
          ),
        ],
      ),
    );
  }
}

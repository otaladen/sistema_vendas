import 'package:flutter/material.dart';

import '../../domain/pdv_consulta_detalhe_linha.dart';
import '../../domain/produto_embalagem.dart';
import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../pdv_texto_destaque_busca.dart';
import 'pdv_consulta_lista_cabecalho.dart';
import 'pdv_consulta_semaforo_estoque.dart';
import 'promocao_badge.dart';

/// Linha da consulta de produtos (colunas fixas + detalhe quando selecionada).
class PdvConsultaLinhaProduto extends StatelessWidget {
  const PdvConsultaLinhaProduto({
    super.key,
    required this.produto,
    required this.termoBusca,
    required this.precoFormatado,
    required this.onAdicionar,
    this.tooltipAdicionar,
    this.emPromocao = false,
    this.precoDeFormatado,
    this.selecionado = false,
    this.quantidadeNoOrcamento = 0,
  });

  final Produto produto;
  final String termoBusca;
  final String precoFormatado;
  final bool emPromocao;
  final String? precoDeFormatado;
  final VoidCallback onAdicionar;
  final String? tooltipAdicionar;
  final bool selecionado;
  final num quantidadeNoOrcamento;

  static const double alturaLinha = 48;
  static const double alturaLinhaComBadges = 58;
  static const double alturaLinhaExpandida = 68;

  static bool exibirBadgesCompactos(Produto produto) {
    return produto.codigoInterno.trim().isNotEmpty ||
        produto.rotuloConversaoEmbalagem.isNotEmpty;
  }

  static double alturaPara({
    required bool expandido,
    required Produto produto,
  }) {
    if (expandido) return alturaLinhaExpandida;
    if (exibirBadgesCompactos(produto)) return alturaLinhaComBadges;
    return alturaLinha;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estiloNome =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final detalhe = selecionado
        ? PdvConsultaDetalheLinhaUtil.montar(
            produto,
            quantidadeNoOrcamento: quantidadeNoOrcamento,
          )
        : '';
    final badgesCompactos =
        !selecionado && exibirBadgesCompactos(produto);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (emPromocao) ...[
                const PromocaoBadge(compacto: true),
                const SizedBox(width: 4),
              ],
              if (quantidadeNoOrcamento > 0 && !selecionado) ...[
                _BadgeOrcamento(
                  produto: produto,
                  quantidade: quantidadeNoOrcamento,
                ),
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
                        linhaSelecionada: selecionado,
                        estiloBase:
                            estiloNome.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraUnidade,
                child: Text(
                  rotuloUnidadeProdutoLista(produto),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSecondaryContainer,
                      ),
                ),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraEstoque,
                child: PdvConsultaSemaforoEstoque(
                  produto: produto,
                  quantidadeNoOrcamento: quantidadeNoOrcamento,
                ),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraPreco,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (precoDeFormatado != null)
                        Text(
                          precoDeFormatado!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                        ),
                      Text(
                        precoFormatado,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: emPromocao
                                      ? PromocaoBadge.corDe(context)
                                      : null,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: PdvConsultaColunas.larguraAcao,
                child: IconButton(
                  tooltip: tooltipAdicionar ?? 'Adicionar 1',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.add_shopping_cart_outlined, size: 20),
                  onPressed: onAdicionar,
                ),
              ),
            ],
          ),
          if (badgesCompactos)
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 2, right: 4),
              child: _BadgesCompactosLinha(produto: produto),
            ),
          if (detalhe.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text(
                detalhe,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgesCompactosLinha extends StatelessWidget {
  const _BadgesCompactosLinha({required this.produto});

  final Produto produto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sku = produto.codigoInterno.trim();
    final emb = produto.rotuloConversaoEmbalagem.trim();

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        if (sku.isNotEmpty)
          _BadgeCompacto(
            rotulo: sku,
            corFundo: scheme.secondaryContainer.withValues(alpha: 0.65),
            corTexto: scheme.onSecondaryContainer,
          ),
        if (emb.isNotEmpty)
          _BadgeCompacto(
            rotulo: emb,
            corFundo: scheme.primaryContainer.withValues(alpha: 0.5),
            corTexto: scheme.onPrimaryContainer,
          ),
      ],
    );
  }
}

class _BadgeCompacto extends StatelessWidget {
  const _BadgeCompacto({
    required this.rotulo,
    required this.corFundo,
    required this.corTexto,
  });

  final String rotulo;
  final Color corFundo;
  final Color corTexto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rotulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: corTexto,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _BadgeOrcamento extends StatelessWidget {
  const _BadgeOrcamento({
    required this.produto,
    required this.quantidade,
  });

  final Produto produto;
  final num quantidade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      produto,
      quantidade.toDouble(),
    );
    return Tooltip(
      message: 'Ja no orcamento: $qTxt',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: scheme.tertiary.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          'Orc.$qTxt',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onTertiaryContainer,
                fontSize: 10,
              ),
        ),
      ),
    );
  }
}

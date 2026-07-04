import 'package:flutter/material.dart';

import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../theme/app_semantic_helper.dart';
import '../widgets/pdv_consulta_semaforo_estoque.dart';
import 'estoque_tabela_colunas.dart';

typedef EstoqueAcaoProduto = void Function(String acao, Produto produto);

/// Linha compacta da tabela de estoque.
class EstoqueTabelaLinha extends StatelessWidget {
  const EstoqueTabelaLinha({
    super.key,
    required this.produto,
    required this.indice,
    required this.criticoPp,
    required this.ppExibicao,
    required this.verCusto,
    required this.vendaFormatada,
    required this.custoFormatado,
    required this.onAcao,
  });

  final Produto produto;
  final int indice;
  final bool criticoPp;
  final double ppExibicao;
  final bool verCusto;
  final String vendaFormatada;
  final String custoFormatado;
  final EstoqueAcaoProduto onAcao;

  static TextStyle? _estiloNumero(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final estiloNum = _estiloNumero(context);
    final zebra = indice.isOdd
        ? scheme.surfaceContainerLowest.withValues(alpha: 0.45)
        : scheme.surface;
    final fundo = criticoPp
        ? Color.alphaBlend(
            semantic.errorBg.withValues(alpha: 0.22),
            zebra,
          )
        : zebra;

    return Material(
      color: fundo,
      child: InkWell(
        onTap: () => onAcao('ajustar', produto),
        hoverColor: scheme.primary.withValues(alpha: 0.05),
        mouseCursor: SystemMouseCursors.click,
        child: SizedBox(
          height: EstoqueTabelaColunas.alturaLinha,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: EstoqueTabelaColunas.larguraSemaforo,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (criticoPp) ...[
                        Tooltip(
                          message: 'Ponto de pedido critico',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
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
                        const SizedBox(width: 4),
                      ],
                      PdvConsultaSemaforoEstoque(produto: produto),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produto.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        produto.codigoInterno.trim().isEmpty
                            ? 'Sem SKU'
                            : produto.codigoInterno.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: EstoqueTabelaColunas.larguraUn,
                  child: Text(
                    rotuloUnidadeProdutoLista(produto),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                _celulaNum(
                  '${produto.estoqueReal}',
                  estiloNum,
                  tooltip: 'Estoque fisico',
                ),
                _celulaNum(
                  '${produto.estoqueReservado}',
                  estiloNum,
                  tooltip: 'Quantidade reservada',
                ),
                _celulaNum(
                  '${produto.quantidadeMinima}',
                  estiloNum,
                  tooltip: 'Estoque minimo',
                ),
                _celulaNum(
                  ppExibicao.toStringAsFixed(1),
                  estiloNum,
                  tooltip: 'Ponto de pedido / limiar',
                ),
                _celulaNum(
                  produto.vendaMediaDiaria.toStringAsFixed(2),
                  estiloNum,
                  largura: EstoqueTabelaColunas.larguraMedia,
                  tooltip: 'Media diaria de vendas (60 dias)',
                ),
                _celulaPreco(vendaFormatada, tooltip: 'Preco de venda a vista'),
                if (verCusto)
                  _celulaPreco(custoFormatado, tooltip: 'Custo medio ou custo cadastrado'),
                SizedBox(
                  width: EstoqueTabelaColunas.larguraAcao,
                  child: PopupMenuButton<String>(
                    tooltip: 'Acoes',
                    padding: EdgeInsets.zero,
                    iconSize: 20,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _celulaNum(
    String valor,
    TextStyle? estilo, {
    double largura = EstoqueTabelaColunas.larguraNum,
    String? tooltip,
  }) {
    final celula = SizedBox(
      width: largura,
      child: Text(
        valor,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: estilo,
      ),
    );
    if (tooltip == null) return celula;
    return Tooltip(message: tooltip, child: celula);
  }

  Widget _celulaPreco(String valor, {String? tooltip}) {
    final celula = SizedBox(
      width: EstoqueTabelaColunas.larguraPreco,
      child: Text(
        valor,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
    if (tooltip == null) return celula;
    return Tooltip(message: tooltip, child: celula);
  }
}

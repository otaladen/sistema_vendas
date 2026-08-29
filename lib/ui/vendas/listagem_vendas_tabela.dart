import 'package:flutter/material.dart';

import 'listagem_venda_item_ui.dart';
import 'listagem_vendas_layout.dart';
import 'listagem_vendas_ordenacao.dart';

typedef ListagemVendaMenuBuilder = List<PopupMenuEntry<String>> Function(
  ListagemVendaItemUi item,
);

typedef ListagemVendaAcaoCallback = void Function(
  String acao,
  ListagemVendaItemUi item,
);

/// Tabela densa de vendas (desktop) com ordenacao por coluna.
class ListagemVendasTabela extends StatefulWidget {
  const ListagemVendasTabela({
    super.key,
    required this.itens,
    required this.onTapItem,
    required this.onAcaoMenu,
    required this.menuBuilder,
    this.temMais = false,
    this.carregandoMais = false,
    this.onChegouAoFim,
  });

  final List<ListagemVendaItemUi> itens;
  final ValueChanged<ListagemVendaItemUi> onTapItem;
  final ListagemVendaAcaoCallback onAcaoMenu;
  final ListagemVendaMenuBuilder menuBuilder;
  final bool temMais;
  final bool carregandoMais;
  final VoidCallback? onChegouAoFim;

  @override
  State<ListagemVendasTabela> createState() => _ListagemVendasTabelaState();
}

class _ListagemVendasTabelaState extends State<ListagemVendasTabela> {
  ListagemVendasColuna _coluna = ListagemVendasColuna.data;
  bool _ascendente = false;
  final ScrollController _scrollController = ScrollController();

  static const double _prefetchPx = 520;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tentarPrefetch());
  }

  @override
  void didUpdateWidget(covariant ListagemVendasTabela oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Apos filtrar/paginar, o offset antigo pode ficar alem do maximo e
    // a barra de rolagem no Windows "trava" (nao arrasta / nao desce).
    if (!identical(oldWidget.itens, widget.itens) ||
        oldWidget.itens.length != widget.itens.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        if (!pos.hasContentDimensions) return;
        final max = pos.maxScrollExtent;
        if (_scrollController.offset > max) {
          _scrollController.jumpTo(max < 0 ? 0 : max);
        }
        _tentarPrefetch();
      });
    } else if (oldWidget.carregandoMais &&
        !widget.carregandoMais &&
        widget.temMais) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tentarPrefetch());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() => _tentarPrefetch();

  void _tentarPrefetch() {
    final cb = widget.onChegouAoFim;
    if (cb == null || !widget.temMais || widget.carregandoMais) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    // Lista curta (cabe na tela) ou perto do fim → puxa o próximo lote.
    if (pos.maxScrollExtent <= 0 ||
        pos.pixels >= pos.maxScrollExtent - _prefetchPx) {
      cb();
    }
  }

  void _alternarOrdenacao(ListagemVendasColuna coluna) {
    setState(() {
      if (_coluna == coluna) {
        _ascendente = !_ascendente;
      } else {
        _coluna = coluna;
        _ascendente = colunaOrdenacaoPadraoAscendente(coluna);
      }
    });
  }

  List<ListagemVendaItemUi> get _itensOrdenados =>
      ordenarItensListagemVendas(
        widget.itens,
        coluna: _coluna,
        ascendente: _ascendente,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itens = _itensOrdenados;

    final corCabecalho = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.07),
      scheme.surfaceContainerHigh,
    );
    final bordaCabecalho = scheme.primary.withValues(alpha: 0.22);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: corCabecalho,
              border: Border(bottom: BorderSide(color: bordaCabecalho)),
            ),
            child: SizedBox(
              height: ListagemVendasLayout.alturaCabecalhoTabela,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colControle,
                      texto: '#',
                      coluna: ListagemVendasColuna.controle,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colDocumento,
                      texto: 'Documento',
                      coluna: ListagemVendasColuna.documento,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colStatus,
                      texto: 'Status',
                      coluna: ListagemVendasColuna.status,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colData,
                      texto: 'Data',
                      coluna: ListagemVendasColuna.data,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    Expanded(
                      flex: ListagemVendasLayout.flexCliente,
                      child: _CabOrdenavel(
                        texto: 'Cliente',
                        coluna: ListagemVendasColuna.cliente,
                        ativa: _coluna,
                        ascendente: _ascendente,
                        onTap: _alternarOrdenacao,
                      ),
                    ),
                    Expanded(
                      flex: ListagemVendasLayout.flexVendedor,
                      child: _CabOrdenavel(
                        texto: 'Vendedor',
                        coluna: ListagemVendasColuna.vendedor,
                        ativa: _coluna,
                        ascendente: _ascendente,
                        onTap: _alternarOrdenacao,
                      ),
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colPagamento,
                      texto: 'Pagamento',
                      coluna: ListagemVendasColuna.pagamento,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colEntrega,
                      texto: 'Entrega',
                      coluna: ListagemVendasColuna.entrega,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      onTap: _alternarOrdenacao,
                    ),
                    _CabOrdenavel(
                      largura: ListagemVendasLayout.colTotal,
                      texto: 'Total',
                      coluna: ListagemVendasColuna.total,
                      ativa: _coluna,
                      ascendente: _ascendente,
                      alinharFim: true,
                      onTap: _alternarOrdenacao,
                    ),
                    const SizedBox(width: ListagemVendasLayout.colAcoes),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView.builder(
                controller: _scrollController,
                primary: false,
                itemCount: itens.length,
                itemExtent: ListagemVendasLayout.alturaLinhaTabela,
                cacheExtent: 400,
                physics: const AlwaysScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final item = itens[index];
                  // Faixa neutra sobre a superficie: precisa aparecer no claro
                  // e no escuro para o olho atravessar a linha inteira.
                  final zebra = index.isOdd
                      ? Color.alphaBlend(
                          scheme.onSurface.withValues(alpha: 0.045),
                          scheme.surface,
                        )
                      : scheme.surface;

                  return Material(
                    color: item.cancelada
                        ? scheme.errorContainer.withValues(alpha: 0.18)
                        : zebra,
                    child: InkWell(
                      onTap: () => widget.onTapItem(item),
                      hoverColor: scheme.primary.withValues(alpha: 0.14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        // Pintada por cima: a linha tem altura fixa e uma
                        // borda no box roubaria 1px do conteudo.
                        foregroundDecoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: scheme.outlineVariant
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: ListagemVendasLayout.colControle,
                              child: _BadgeNumero(texto: item.badgeNumero),
                            ),
                            SizedBox(
                              width: ListagemVendasLayout.colDocumento,
                              child: Text(
                                item.titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: item.cancelada
                                      ? scheme.error
                                      : scheme.onSurface,
                                  decoration: item.cancelada
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: ListagemVendasLayout.colStatus,
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  _StatusChip(
                                    texto: item.status,
                                    cor: item.statusCor,
                                    detalhe: item.statusDetalhe,
                                  ),
                                  if (item.temDevolucaoTroca)
                                    _StatusChip(
                                      texto: 'Dev/Troca',
                                      cor: Colors.deepOrange,
                                      detalhe: 'Venda com devolucao ou troca',
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: ListagemVendasLayout.colData,
                              child: Text(
                                item.dataHora,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              flex: ListagemVendasLayout.flexCliente,
                              child: Text(
                                item.cliente,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: ListagemVendasLayout.flexVendedor,
                              child: Text(
                                item.vendedor,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                              SizedBox(
                                width: ListagemVendasLayout.colPagamento,
                                child: Text(
                                  item.pagamento,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                              SizedBox(
                                width: ListagemVendasLayout.colEntrega,
                                child: Text(
                                  item.entrega,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: ListagemVendasLayout.colTotal,
                                child: Text(
                                  item.totalFormatado,
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: item.cancelada
                                        ? scheme.error
                                        : scheme.primary,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Acoes',
                                onSelected: (v) =>
                                    widget.onAcaoMenu(v, item),
                                itemBuilder: (_) => widget.menuBuilder(item),
                                child: const SizedBox(
                                  width: ListagemVendasLayout.colAcoes,
                                  child: Icon(Icons.more_vert, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                },
              ),
            ),
          ),
          if (widget.carregandoMais)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _CabOrdenavel extends StatelessWidget {
  const _CabOrdenavel({
    required this.texto,
    required this.coluna,
    required this.ativa,
    required this.ascendente,
    required this.onTap,
    this.largura,
    this.alinharFim = false,
  });

  final String texto;
  final ListagemVendasColuna coluna;
  final ListagemVendasColuna ativa;
  final bool ascendente;
  final void Function(ListagemVendasColuna) onTap;
  final double? largura;
  final bool alinharFim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selecionada = ativa == coluna;
    final icone = !selecionada
        ? Icons.unfold_more_rounded
        : ascendente
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;

    final conteudo = InkWell(
      onTap: () => onTap(coluna),
      borderRadius: BorderRadius.circular(6),
      hoverColor: scheme.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisAlignment:
              alinharFim ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                texto.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alinharFim ? TextAlign.right : TextAlign.left,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                      color: selecionada
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              icone,
              size: 14,
              color: selecionada
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );

    if (largura != null) {
      return SizedBox(width: largura, child: conteudo);
    }
    return conteudo;
  }
}

class _BadgeNumero extends StatelessWidget {
  const _BadgeNumero({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.texto,
    required this.cor,
    this.detalhe,
  });

  final String texto;
  final Color cor;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        texto,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cor,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
      ),
    );

    final msg = detalhe?.trim();
    if (msg == null || msg.isEmpty || msg == texto) {
      return chip;
    }
    final scheme = Theme.of(context).colorScheme;
    // Balao escuro e afastado: solto sobre a linha de baixo, ele era lido como
    // se fosse o status daquela outra venda.
    return Tooltip(
      message: msg,
      verticalOffset: 24,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onInverseSurface,
            fontWeight: FontWeight.w600,
          ),
      child: chip,
    );
  }
}

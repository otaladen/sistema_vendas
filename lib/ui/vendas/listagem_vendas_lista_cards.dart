import 'package:flutter/material.dart';

import 'listagem_venda_item_ui.dart';

typedef ListagemVendaMenuBuilder = List<PopupMenuEntry<String>> Function(
  ListagemVendaItemUi item,
);

typedef ListagemVendaAcaoCallback = void Function(
  String acao,
  ListagemVendaItemUi item,
);

/// Cards compactos para listagem em telas estreitas.
class ListagemVendasListaCards extends StatefulWidget {
  const ListagemVendasListaCards({
    super.key,
    required this.itens,
    required this.onTapItem,
    required this.onAcaoMenu,
    required this.menuBuilder,
  });

  final List<ListagemVendaItemUi> itens;
  final ValueChanged<ListagemVendaItemUi> onTapItem;
  final ListagemVendaAcaoCallback onAcaoMenu;
  final ListagemVendaMenuBuilder menuBuilder;

  @override
  State<ListagemVendasListaCards> createState() =>
      _ListagemVendasListaCardsState();
}

class _ListagemVendasListaCardsState extends State<ListagemVendasListaCards> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant ListagemVendasListaCards oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      interactive: true,
      child: ListView.separated(
        controller: _scrollController,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.itens.length,
        separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = widget.itens[index];
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;

          return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onTapItem(item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          item.badgeNumero,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.titulo,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration: item.cancelada
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: item.cancelada ? scheme.error : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.dataHora,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        item.totalFormatado,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: item.cancelada
                              ? scheme.error
                              : scheme.primary,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => widget.onAcaoMenu(v, item),
                        itemBuilder: (_) => widget.menuBuilder(item),
                        child: const Icon(Icons.more_vert),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ChipInfo(
                        texto: item.status,
                        cor: item.statusCor,
                      ),
                      _ChipInfo(
                        texto: item.pagamento,
                        cor: scheme.secondary,
                      ),
                      _ChipInfo(
                        texto: item.entrega,
                        cor: scheme.tertiary,
                      ),
                      if (item.temDevolucaoTroca)
                        _ChipInfo(
                          texto: 'Dev/Troca',
                          cor: Colors.deepOrange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.cliente,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    item.vendedor,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (item.alertas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final alerta in item.alertas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          alerta,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

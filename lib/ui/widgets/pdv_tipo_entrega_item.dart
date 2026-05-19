import 'package:flutter/material.dart';

import '../../domain/entrega_venda_helper.dart';

/// Botao compacto para alternar tipo de entrega do item do carrinho (PDV).
class PdvBotaoTipoEntregaItem extends StatelessWidget {
  const PdvBotaoTipoEntregaItem({
    super.key,
    required this.tipoEntregaItem,
    required this.onPressed,
    this.compacto = false,
  });

  final String tipoEntregaItem;
  final VoidCallback onPressed;
  final bool compacto;

  static IconData iconePara(String tipo) {
    switch (EntregaVendaHelper.normalizarTipoItem(tipo)) {
      case EntregaVendaHelper.tipoEntregaLoja:
        return Icons.local_shipping_outlined;
      case EntregaVendaHelper.tipoRetiradaFutura:
        return Icons.schedule_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static Color? corPara(BuildContext context, String tipo) {
    final scheme = Theme.of(context).colorScheme;
    switch (EntregaVendaHelper.normalizarTipoItem(tipo)) {
      case EntregaVendaHelper.tipoEntregaLoja:
        return scheme.tertiary;
      case EntregaVendaHelper.tipoRetiradaFutura:
        return scheme.primary;
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(tipoEntregaItem);
    final rotulo = EntregaVendaHelper.rotuloTipoItem(tipo);
    final emoji = EntregaVendaHelper.emojiTipoItem(tipo);
    return IconButton(
      onPressed: onPressed,
      tooltip: '$emoji $rotulo — toque para alternar',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.all(compacto ? 2 : 4),
      constraints: BoxConstraints(
        minWidth: compacto ? 30 : 36,
        minHeight: compacto ? 30 : 36,
      ),
      icon: Icon(
        iconePara(tipo),
        size: compacto ? 18 : 22,
        color: corPara(context, tipo),
      ),
    );
  }
}

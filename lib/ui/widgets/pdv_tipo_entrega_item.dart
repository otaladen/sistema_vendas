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
    final rotuloCompleto = EntregaVendaHelper.rotuloTipoItem(tipo);
    final rotuloCurto = EntregaVendaHelper.rotuloCurtoTipoItem(tipo);
    final emoji = EntregaVendaHelper.emojiTipoItem(tipo);
    final cor = corPara(context, tipo);
    final theme = Theme.of(context);

    return Tooltip(
      message: '$emoji $rotuloCompleto — toque para alternar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compacto ? 4 : 6,
              vertical: compacto ? 4 : 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconePara(tipo),
                  size: compacto ? 16 : 20,
                  color: cor,
                ),
                SizedBox(width: compacto ? 3 : 4),
                Text(
                  rotuloCurto,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: compacto ? 11 : 12,
                    color: cor,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

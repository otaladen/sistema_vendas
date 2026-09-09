import 'package:flutter/material.dart';

import '../../domain/entrega_venda_helper.dart';
import '../theme/app_semantic_colors.dart';

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

  static AppSemanticColors _semantic(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ??
      AppSemanticColors.claro;

  /// Fundo claro da linha: leva agora verde, carreto amarelo, futura vermelho.
  static Color fundoPara(BuildContext context, String tipo) {
    final s = _semantic(context);
    switch (EntregaVendaHelper.normalizarTipoItem(tipo)) {
      case EntregaVendaHelper.tipoEntregaLoja:
        return s.warningBg;
      case EntregaVendaHelper.tipoRetiradaFutura:
        return s.errorBg;
      default:
        return s.successBg;
    }
  }

  static Color bordaPara(BuildContext context, String tipo) {
    final s = _semantic(context);
    switch (EntregaVendaHelper.normalizarTipoItem(tipo)) {
      case EntregaVendaHelper.tipoEntregaLoja:
        return s.warningBorder;
      case EntregaVendaHelper.tipoRetiradaFutura:
        return s.errorBorder;
      default:
        return s.successBorder;
    }
  }

  static Color corPara(BuildContext context, String tipo) {
    final s = _semantic(context);
    switch (EntregaVendaHelper.normalizarTipoItem(tipo)) {
      case EntregaVendaHelper.tipoEntregaLoja:
        return s.warningFg;
      case EntregaVendaHelper.tipoRetiradaFutura:
        return s.errorFg;
      default:
        return s.successFg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(tipoEntregaItem);
    final rotuloCompleto = EntregaVendaHelper.rotuloTipoItem(tipo);
    final rotuloExibicao = compacto
        ? EntregaVendaHelper.abreviacaoTipoItem(tipo)
        : EntregaVendaHelper.rotuloCurtoTipoItem(tipo);
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
              horizontal: compacto ? 3 : 5,
              vertical: compacto ? 2 : 4,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconePara(tipo),
                    size: compacto ? 14 : 18,
                    color: cor,
                  ),
                  SizedBox(width: compacto ? 2 : 4),
                  Text(
                    rotuloExibicao,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: compacto ? 10 : 11,
                      color: cor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

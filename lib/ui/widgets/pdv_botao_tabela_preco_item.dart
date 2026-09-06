import 'package:flutter/material.dart';

import '../../domain/pdv_tabela_preco_util.dart';

/// Botao compacto para alternar tabela de preco da linha do carrinho (PDV).
class PdvBotaoTabelaPrecoItem extends StatelessWidget {
  const PdvBotaoTabelaPrecoItem({
    super.key,
    required this.precoTipo,
    required this.onPressed,
    this.compacto = false,
  });

  final String precoTipo;
  final VoidCallback onPressed;
  final bool compacto;

  static Color? corPara(BuildContext context, String precoTipo) {
    final scheme = Theme.of(context).colorScheme;
    switch (PdvTabelaPrecoUtil.normalizar(precoTipo)) {
      case 'preco2':
        return scheme.tertiary;
      case 'preco3':
        return scheme.secondary;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rotulo = PdvTabelaPrecoUtil.rotuloCurto(precoTipo);
    final cor = corPara(context, precoTipo);
    return IconButton(
      onPressed: onPressed,
      tooltip:
          '${PdvTabelaPrecoUtil.rotulo(precoTipo)} — toque para alternar (F1–F3 na linha)',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.all(compacto ? 2 : 4),
      constraints: BoxConstraints(
        minWidth: compacto ? 28 : 34,
        minHeight: compacto ? 24 : 30,
      ),
      icon: Text(
        rotulo,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: compacto ? 10 : 11,
          color: cor,
        ),
      ),
    );
  }
}

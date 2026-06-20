import 'package:flutter/material.dart';

/// Selo compacto de item em promocao (PDV / carrinho).
class PromocaoBadge extends StatelessWidget {
  const PromocaoBadge({super.key, this.compacto = false});

  final bool compacto;

  static Color corDe(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  @override
  Widget build(BuildContext context) {
    final cor = corDe(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 5 : 6,
        vertical: compacto ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'PROMO',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: compacto ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          height: 1.1,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';

/// Badge compacto da unidade de venda (evita erro de quantidade no balcao).
class ProdutoUnidadeChip extends StatelessWidget {
  const ProdutoUnidadeChip({
    super.key,
    required this.produto,
    this.compacto = false,
  });

  final Produto produto;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rotulo = rotuloUnidadeProdutoLista(produto);
    return Tooltip(
      message: produto.permiteQuantidadeFracionada
          ? 'Unidade $rotulo · quantidade fracionada permitida'
          : 'Unidade de venda: $rotulo',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 6 : 8,
          vertical: compacto ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          rotulo,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSecondaryContainer,
                letterSpacing: 0.3,
              ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../model/produto.dart';

/// Resumo explicito de estoque para PDV: fisico, reservado e disponivel.
class PdvEstoqueResumoPanel extends StatelessWidget {
  const PdvEstoqueResumoPanel({
    super.key,
    required this.produto,
    this.compacto = false,
    this.quantidadeNoOrcamento = 0,
  });

  final Produto produto;
  final bool compacto;
  /// Quantidade deste produto ja no carrinho/orcamento (unidade de estoque).
  final int quantidadeNoOrcamento;

  bool get _critico =>
      produto.estoqueReal < produto.quantidadeMinima && produto.estoqueReal > 0;

  bool get _zerado => produto.estoqueReal <= 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disponivel = produto.estoqueLivreParaVenda;
    final fisico = produto.estoqueReal;
    final reservado = produto.estoqueReservado;
    final noOrcamento = quantidadeNoOrcamento.clamp(0, 1 << 30);
    final restanteAposOrcamento = disponivel - noOrcamento;

    Color corDisponivel = scheme.primary;
    if (_zerado) {
      corDisponivel = scheme.error;
    } else if (_critico || disponivel <= 0 || restanteAposOrcamento < 0) {
      corDisponivel = scheme.error;
    } else if (disponivel <= produto.quantidadeMinima ||
        restanteAposOrcamento <= produto.quantidadeMinima) {
      corDisponivel = scheme.tertiary;
    }

    if (compacto) {
      final linhaOrcamento = noOrcamento > 0
          ? ' · Orc. $noOrcamento · Rest. $restanteAposOrcamento'
          : '';
      return Tooltip(
        message:
            'Disponivel: $disponivel · Fisico: $fisico · Reservado: $reservado'
            '$linhaOrcamento',
        child: Text(
          'Disp. $disponivel · Fis. $fisico · Res. $reservado$linhaOrcamento',
          style: theme.textTheme.labelSmall?.copyWith(
            color: corDisponivel,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: corDisponivel.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estoque',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Disponivel',
                  valor: '$disponivel',
                  destaque: true,
                  cor: corDisponivel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Fisico',
                  valor: '$fisico',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Reservado',
                  valor: '$reservado',
                ),
              ),
            ],
          ),
          if (reservado > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Reservado = retirada futura / carreto pendente.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (noOrcamento > 0) ...[
            const SizedBox(height: 6),
            Text(
              restanteAposOrcamento < 0
                  ? 'Neste orcamento: $noOrcamento · Restante: $restanteAposOrcamento (acima do disponivel)'
                  : 'Neste orcamento: $noOrcamento · Restante: $restanteAposOrcamento',
              style: theme.textTheme.labelSmall?.copyWith(
                color: restanteAposOrcamento < 0
                    ? scheme.error
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _celula(
    BuildContext context, {
    required String rotulo,
    required String valor,
    bool destaque = false,
    Color? cor,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          valor,
          style: (destaque
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.titleSmall)
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color: cor,
          ),
        ),
      ],
    );
  }
}

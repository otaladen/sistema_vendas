import 'package:flutter/material.dart';

import 'estoque_tabela_colunas.dart';

class EstoqueTabelaCabecalho extends StatelessWidget {
  const EstoqueTabelaCabecalho({
    super.key,
    required this.verCusto,
  });

  final bool verCusto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estilo = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.15,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: SizedBox(
        height: EstoqueTabelaColunas.alturaCabecalho,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _coluna(
                'Est.',
                EstoqueTabelaColunas.larguraSemaforo,
                estilo,
                tooltip: 'Disponivel para venda (semaforo)',
                align: TextAlign.end,
              ),
              Expanded(
                child: Text('Produto / SKU', style: estilo),
              ),
              _coluna('Un.', EstoqueTabelaColunas.larguraUn, estilo,
                  tooltip: 'Unidade de venda', align: TextAlign.center),
              _coluna('Fis.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Estoque fisico', align: TextAlign.end),
              _coluna('Res.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Reservado', align: TextAlign.end),
              _coluna('Min.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Quantidade minima', align: TextAlign.end),
              _coluna('PP', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Ponto de pedido', align: TextAlign.end),
              _coluna('Media', EstoqueTabelaColunas.larguraMedia, estilo,
                  tooltip: 'Media diaria de vendas', align: TextAlign.end),
              _coluna('Venda', EstoqueTabelaColunas.larguraPreco, estilo,
                  tooltip: 'Preco de venda a vista', align: TextAlign.end),
              if (verCusto)
                _coluna('Custo', EstoqueTabelaColunas.larguraPreco, estilo,
                    tooltip: 'Custo medio ou cadastrado', align: TextAlign.end),
              SizedBox(width: EstoqueTabelaColunas.larguraAcao),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coluna(
    String rotulo,
    double largura,
    TextStyle? estilo, {
    String? tooltip,
    TextAlign align = TextAlign.start,
  }) {
    final texto = Text(rotulo, style: estilo, textAlign: align);
    return SizedBox(
      width: largura,
      child: tooltip == null
          ? texto
          : Tooltip(message: tooltip, child: texto),
    );
  }
}

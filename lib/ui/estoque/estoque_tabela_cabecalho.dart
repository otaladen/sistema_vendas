import 'package:flutter/material.dart';

import 'estoque_lista_metricas.dart';
import 'estoque_tabela_colunas.dart';

typedef EstoqueOrdenarColuna = void Function(EstoqueColunaOrdenacao coluna);

class EstoqueTabelaCabecalho extends StatelessWidget {
  const EstoqueTabelaCabecalho({
    super.key,
    required this.verCusto,
    required this.colunaOrdenacao,
    required this.ordenacaoAscendente,
    required this.onOrdenar,
  });

  final bool verCusto;
  final EstoqueColunaOrdenacao colunaOrdenacao;
  final bool ordenacaoAscendente;
  final EstoqueOrdenarColuna onOrdenar;

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
              _colunaOrdenavel(
                'Disp.',
                EstoqueTabelaColunas.larguraNum,
                estilo,
                corAtiva: scheme.primary,
                coluna: EstoqueColunaOrdenacao.disponivel,
                tooltip: 'Estoque livre (fisico - reservado)',
              ),
              _coluna('Fís.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Estoque fisico', align: TextAlign.end),
              _coluna('Res.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Reservado', align: TextAlign.end),
              _coluna('Mín.', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Quantidade minima', align: TextAlign.end),
              _coluna('PP', EstoqueTabelaColunas.larguraNum, estilo,
                  tooltip: 'Ponto de pedido', align: TextAlign.end),
              _colunaOrdenavel(
                'Média',
                EstoqueTabelaColunas.larguraMedia,
                estilo,
                corAtiva: scheme.primary,
                coluna: EstoqueColunaOrdenacao.media,
                tooltip: 'Media diaria de vendas',
              ),
              _colunaOrdenavel(
                'Venda',
                EstoqueTabelaColunas.larguraPreco,
                estilo,
                corAtiva: scheme.primary,
                coluna: EstoqueColunaOrdenacao.venda,
                tooltip: 'Preco 2',
              ),
              if (verCusto)
                _coluna('Custo', EstoqueTabelaColunas.larguraPreco, estilo,
                    tooltip: 'Custo medio ou cadastrado', align: TextAlign.end),
              if (verCusto)
                _colunaOrdenavel(
                  'Marg.%',
                  EstoqueTabelaColunas.larguraMargem,
                  estilo,
                  corAtiva: scheme.primary,
                  coluna: EstoqueColunaOrdenacao.margem,
                  tooltip: 'Margem sobre o preco de venda',
                ),
              _colunaOrdenavel(
                'Cob.',
                EstoqueTabelaColunas.larguraCobertura,
                estilo,
                corAtiva: scheme.primary,
                coluna: EstoqueColunaOrdenacao.cobertura,
                tooltip: 'Dias de estoque livre (media diaria)',
              ),
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

  Widget _colunaOrdenavel(
    String rotulo,
    double largura,
    TextStyle? estilo, {
    required Color corAtiva,
    required EstoqueColunaOrdenacao coluna,
    required String tooltip,
  }) {
    final ativa = colunaOrdenacao == coluna;
    final icone = !ativa
        ? Icons.unfold_more_rounded
        : ordenacaoAscendente
            ? Icons.arrow_drop_up_rounded
            : Icons.arrow_drop_down_rounded;

    return SizedBox(
      width: largura,
      child: Tooltip(
        message: '$tooltip · clique para ordenar',
        child: InkWell(
          onTap: () => onOrdenar(coluna),
          borderRadius: BorderRadius.circular(4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  rotulo,
                  style: estilo?.copyWith(
                    color: ativa ? corAtiva : estilo.color,
                    decoration: ativa ? TextDecoration.underline : null,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                icone,
                size: 16,
                color: ativa
                    ? corAtiva
                    : estilo?.color?.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

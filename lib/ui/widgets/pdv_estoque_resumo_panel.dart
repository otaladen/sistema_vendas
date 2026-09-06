import 'package:flutter/material.dart';

import '../../domain/pdv_consulta_multi_deposito_util.dart';
import '../../domain/pdv_estoque_semaforo_util.dart';
import '../../domain/produto_embalagem.dart';
import '../../model/produto.dart';
import 'pdv_consulta_semaforo_estoque.dart';

/// Resumo explicito de estoque para PDV: fisico, reservado e disponivel.
class PdvEstoqueResumoPanel extends StatelessWidget {
  const PdvEstoqueResumoPanel({
    super.key,
    required this.produto,
    this.compacto = false,
    this.quantidadeNoOrcamento = 0,
    this.rotulosDeposito = const PdvConsultaDepositoRotulos(),
  });

  final Produto produto;
  final bool compacto;
  /// Quantidade deste produto ja no carrinho/orcamento (unidade de estoque).
  final num quantidadeNoOrcamento;
  final PdvConsultaDepositoRotulos rotulosDeposito;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disponivel = produto.estoqueLivreParaVenda;
    final disponivelExib = produto.estoqueLivreExibicao;
    final reservadoExib = ProdutoEmbalagem.valorEstoqueExibicao(
      produto,
      produto.estoqueReservado,
    );
    final noOrcamento = quantidadeNoOrcamento.clamp(0, 1 << 30).toDouble();
    final restanteAposOrcamento = disponivelExib - noOrcamento;
    final noOrcTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      produto,
      noOrcamento,
    );
    final restanteTxt = ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
      produto,
      restanteAposOrcamento.clamp(0, double.infinity),
    );
    final nivel = PdvEstoqueSemaforoUtil.nivelDe(
      produto,
      quantidadeNoOrcamento: noOrcamento,
    );
    final corDisponivel = PdvEstoqueSemaforoUtil.corDe(context, nivel);
    final dispTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      disponivel,
      comUnidade: true,
    );
    final fisTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReal,
      comUnidade: true,
    );
    final resTxt = ProdutoEmbalagem.formatarEstoque(
      produto,
      produto.estoqueReservado,
      comUnidade: true,
    );
    final unidade = ProdutoEmbalagem.normalizarUnidade(produto.unidade);
    final rotuloNivel = PdvEstoqueSemaforoUtil.rotuloNivel(nivel);

    if (compacto) {
      final linhaCd = PdvConsultaMultiDepositoUtil.exibirCd(produto)
          ? ' · ${rotulosDeposito.cd} ${produto.estoqueCd}'
          : '';
      final linhaOrcamento = noOrcamento > 0
          ? ' · Orc. $noOrcTxt · Rest. $restanteTxt'
          : '';
      final acimaDisponivel = restanteAposOrcamento < 0;
      return Tooltip(
        message: PdvEstoqueSemaforoUtil.tooltipDe(
          produto,
          quantidadeNoOrcamento: noOrcamento,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Disp. $dispTxt · Fis. $fisTxt · Res. $resTxt$linhaCd$linhaOrcamento',
              style: theme.textTheme.labelSmall?.copyWith(
                color: corDisponivel,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (acimaDisponivel) ...[
              const SizedBox(height: 4),
              Text(
                'Quantidade no orcamento acima do estoque disponivel',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estoque · $rotuloNivel',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              PdvConsultaSemaforoEstoque(
                produto: produto,
                quantidadeNoOrcamento: noOrcamento,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Disponivel',
                  valor: dispTxt,
                  destaque: true,
                  cor: corDisponivel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Fisico',
                  valor: fisTxt,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _celula(
                  context,
                  rotulo: 'Reservado',
                  valor: resTxt,
                ),
              ),
            ],
          ),
          if (PdvConsultaMultiDepositoUtil.exibirCd(produto)) ...[
            const SizedBox(height: 6),
            Text(
              '${rotulosDeposito.cd}: ${produto.estoqueCd} $unidade',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.secondary,
              ),
            ),
          ],
          if (reservadoExib > 0) ...[
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
                  ? 'Neste orcamento: $noOrcTxt · Restante: $restanteTxt (acima do disponivel)'
                  : 'Neste orcamento: $noOrcTxt · Restante: $restanteTxt',
              style: theme.textTheme.labelSmall?.copyWith(
                color: restanteAposOrcamento < 0
                    ? scheme.error
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (restanteAposOrcamento < 0) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Quantidade no orcamento acima do estoque disponivel',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
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
                  ? theme.textTheme.bodyLarge
                  : theme.textTheme.bodyMedium)
              ?.copyWith(
            fontWeight: FontWeight.w700,
            color: cor,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_semantic_helper.dart';

final NumberFormat _moedaKpi = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// KPIs da equipe no topo do cadastro de funcionarios.
class FuncionarioEquipeKpis extends StatelessWidget {
  const FuncionarioEquipeKpis({
    super.key,
    required this.totalCadastrados,
    required this.totalAtivos,
    required this.folhaBaseAtivos,
  });

  final int totalCadastrados;
  final int totalAtivos;
  final double folhaBaseAtivos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final scheme = theme.colorScheme;
    final inativos = totalCadastrados - totalAtivos;

    return LayoutBuilder(
      builder: (context, c) {
        final colunaUnica = c.maxWidth < 520;
        final cards = [
          _KpiEquipe(
            icone: Icons.groups_outlined,
            rotulo: 'Cadastrados',
            valor: '$totalCadastrados',
            detalhe: '$totalAtivos ativo(s) · $inativos inativo(s)',
            cor: scheme.onSurfaceVariant,
            bg: scheme.surfaceContainerHighest,
          ),
          _KpiEquipe(
            icone: Icons.badge_outlined,
            rotulo: 'Equipe ativa',
            valor: '$totalAtivos',
            detalhe: totalCadastrados == 0
                ? 'Nenhum cadastro'
                : '${((totalAtivos / totalCadastrados) * 100).round()}% do quadro',
            cor: semantic.successFg,
            bg: semantic.successBg,
          ),
          _KpiEquipe(
            icone: Icons.payments_outlined,
            rotulo: 'Folha base (ativos)',
            valor: _moedaKpi.format(folhaBaseAtivos),
            detalhe: 'Soma dos salarios cadastrados',
            cor: semantic.infoFg,
            bg: semantic.infoBg,
          ),
        ];

        if (colunaUnica) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _KpiEquipe extends StatelessWidget {
  const _KpiEquipe({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.detalhe,
    required this.cor,
    required this.bg,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final String detalhe;
  final Color cor;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalhe,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

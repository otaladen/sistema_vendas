import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/financeiro_resumo.dart';
import '../../theme/app_modulo_cores.dart';
import '../../theme/app_semantic_colors.dart';
import '../../theme/app_semantic_helper.dart';

final NumberFormat _moedaHub = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

/// Painel executivo AR + AP + caixa no hub financeiro.
class FinanceiroResumoPainel extends StatelessWidget {
  const FinanceiroResumoPainel({
    super.key,
    required this.resumo,
    this.onTapAReceber,
    this.onTapAReceberVencido,
    this.onTapAPagar,
    this.onTapAPagarAtrasado,
    this.onTapSaldoProjetado,
  });

  final FinanceiroResumoSnapshot resumo;
  final VoidCallback? onTapAReceber;
  final VoidCallback? onTapAReceberVencido;
  final VoidCallback? onTapAPagar;
  final VoidCallback? onTapAPagarAtrasado;
  final VoidCallback? onTapSaldoProjetado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final scheme = theme.colorScheme;
    final saldo = resumo.saldoLiquidoProjetado;
    final saldoPositivo = saldo >= 0;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final colunaUnica = w < 560;
        final gridDuasColunas = w >= 560 && w < 960;

        final cards = [
          _KpiFinanceiro(
            icone: Icons.call_received_outlined,
            rotulo: 'A receber (fiado)',
            valor: _moedaHub.format(resumo.totalAReceber),
            detalhe:
                '${resumo.qtdTitulosReceberAbertos} titulo(s) · vencido ${_moedaHub.format(resumo.aReceberVencido)}',
            cor: AppModuloCores.modulo(context, AppModuloId.contasReceber),
            bg: semantic.infoBg,
            onTap: onTapAReceber,
          ),
          _KpiFinanceiro(
            icone: Icons.warning_amber_rounded,
            rotulo: 'Fiado vencido',
            valor: _moedaHub.format(resumo.aReceberVencido),
            detalhe: resumo.aReceberVenceHoje > 0
                ? 'Hoje: ${_moedaHub.format(resumo.aReceberVenceHoje)}'
                : 'Prox. 7d: ${_moedaHub.format(resumo.aReceberProximos7)}',
            cor: semantic.errorFg,
            bg: semantic.errorBg,
            onTap: onTapAReceberVencido,
            destaque: resumo.aReceberVencido > 0.01,
          ),
          _KpiFinanceiro(
            icone: Icons.call_made_outlined,
            rotulo: 'A pagar',
            valor: _moedaHub.format(resumo.totalAPagarPendente),
            detalhe:
                '${resumo.qtdContasPagarAbertas} parcela(s) · atraso ${_moedaHub.format(resumo.aPagarAtrasado)}',
            cor: scheme.secondary,
            bg: scheme.surfaceContainerHighest,
            onTap: onTapAPagar,
          ),
          _KpiFinanceiro(
            icone: Icons.event_busy_outlined,
            rotulo: 'Pagar vencido',
            valor: _moedaHub.format(resumo.aPagarAtrasado),
            detalhe: resumo.aPagarProximos7 > 0
                ? '7 dias: ${_moedaHub.format(resumo.aPagarProximos7)}'
                : '${resumo.qtdContasPagarAtrasadas} parcela(s)',
            cor: AppModuloCores.harmonizar(scheme, 320),
            bg: semantic.errorBg.withValues(alpha: 0.55),
            onTap: onTapAPagarAtrasado,
            destaque: resumo.aPagarAtrasado > 0.01,
          ),
        ];

        Widget gradeKpis() {
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
          if (gridDuasColunas) {
            return Column(
              children: [
                for (var i = 0; i < cards.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[i]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i + 1 < cards.length
                            ? cards[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FaixaSaldoProjetado(
              saldo: saldo,
              positivo: saldoPositivo,
              resumo: resumo,
              onTap: onTapSaldoProjetado,
            ),
            if (resumo.caixaAberto) ...[
              const SizedBox(height: 10),
              _FaixaCaixaAberto(resumo: resumo, semantic: semantic),
            ],
            if (resumo.semMovimentacaoFinanceira) ...[
              const SizedBox(height: 10),
              _FaixaSemMovimentacao(scheme: scheme),
            ],
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerLow,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insights_outlined,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Indicadores',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    gradeKpis(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FaixaSaldoProjetado extends StatelessWidget {
  const _FaixaSaldoProjetado({
    required this.saldo,
    required this.positivo,
    required this.resumo,
    this.onTap,
  });

  final double saldo;
  final bool positivo;
  final FinanceiroResumoSnapshot resumo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cor = positivo ? scheme.tertiary : scheme.error;
    final bgInicio = positivo
        ? scheme.primaryContainer.withValues(alpha: 0.85)
        : scheme.errorContainer.withValues(alpha: 0.55);
    final bgFim = scheme.surfaceContainerHighest;

    final conteudo = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [bgInicio, bgFim],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saldo projetado',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _moedaHub.format(saldo),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Caixa ref. ${_moedaHub.format(resumo.saldoCaixaEstimado ?? 0)}'
            ' + receber ${_moedaHub.format(resumo.totalAReceber)}'
            ' − pagar ${_moedaHub.format(resumo.totalAPagarPendente)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return conteudo;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: conteudo,
      ),
    );
  }
}

class _FaixaCaixaAberto extends StatelessWidget {
  const _FaixaCaixaAberto({required this.resumo, required this.semantic});

  final FinanceiroResumoSnapshot resumo;
  final AppSemanticColors? semantic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: semantic?.successBg ?? Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: semantic?.successBorder ?? Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.point_of_sale_outlined,
            color: semantic?.successFg ?? Colors.green.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Caixa aberto'
              '${resumo.operadorCaixa.isNotEmpty ? ' · ${resumo.operadorCaixa}' : ''}'
              '${resumo.saldoCaixaEstimado != null ? ' · saldo ref. ${_moedaHub.format(resumo.saldoCaixaEstimado!)}' : ''}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaixaSemMovimentacao extends StatelessWidget {
  const _FaixaSemMovimentacao({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nenhum titulo em aberto no momento. Use os modulos abaixo para '
              'registrar despesas ou acompanhar fiados.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiFinanceiro extends StatelessWidget {
  const _KpiFinanceiro({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.detalhe,
    required this.cor,
    required this.bg,
    this.onTap,
    this.destaque = false,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final String detalhe;
  final Color cor;
  final Color bg;
  final VoidCallback? onTap;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: destaque ? cor : cor.withValues(alpha: 0.25),
          width: destaque ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cor.withValues(alpha: 0.95),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detalhe,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
    );
  }
}

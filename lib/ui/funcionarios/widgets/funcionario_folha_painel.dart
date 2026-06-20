import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/funcionario_folha_resumo.dart';
import '../../theme/app_semantic_helper.dart';

final NumberFormat _moedaPainel =
    NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final DateFormat _mesCurto = DateFormat('MMM/yy', 'pt_BR');

/// Painel de folha integrada (Fase C): fechamento, alertas, exportacao.
class FuncionarioFolhaPainel extends StatelessWidget {
  const FuncionarioFolhaPainel({
    super.key,
    required this.mesReferencia,
    required this.resumoMes,
    required this.mesFechado,
    required this.contaPagarId,
    required this.alertasEquipe,
    required this.historico12Meses,
    required this.onFecharMes,
    required this.onReabrirMes,
    required this.onExportarFolhaEquipe,
    required this.onExportarLancamentosAno,
    required this.onRelatorioSetor,
    this.compact = false,
  });

  final DateTime mesReferencia;
  final FuncionarioMesResumo? resumoMes;
  final bool mesFechado;
  final int contaPagarId;
  final List<FuncionarioFolhaAlerta> alertasEquipe;
  final List<FolhaMesHistoricoItem> historico12Meses;
  final VoidCallback onFecharMes;
  final VoidCallback onReabrirMes;
  final VoidCallback onExportarFolhaEquipe;
  final VoidCallback onExportarLancamentosAno;
  final VoidCallback onRelatorioSetor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final mesLabel = DateFormat('MMMM/yyyy', 'pt_BR').format(mesReferencia);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (alertasEquipe.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: semantic.warningBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: semantic.warningBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: semantic.warningFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Alertas RH — $mesLabel (${alertasEquipe.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final a in alertasEquipe.take(compact ? 3 : 8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• ${a.codigo} ${a.nome}: ${a.mensagem}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (compact && alertasEquipe.length > 3)
                  Text(
                    '+ ${alertasEquipe.length - 3} alerta(s)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mesFechado
                ? semantic.successBg
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    mesFechado
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                    size: 20,
                    color: mesFechado
                        ? semantic.successFg
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mesFechado
                          ? 'Mes fechado — $mesLabel'
                          : 'Mes aberto — $mesLabel',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (mesFechado && contaPagarId > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('AP #$contaPagarId'),
                    ),
                ],
              ),
              if (resumoMes != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _MetricaFolha(
                      rotulo: 'Liquido',
                      valor: _moedaPainel.format(resumoMes!.liquidoApagar),
                      destaque: true,
                    ),
                    _MetricaFolha(
                      rotulo: 'Vales',
                      valor: _moedaPainel.format(resumoMes!.totalVales),
                    ),
                    _MetricaFolha(
                      rotulo: 'Qtd vales',
                      valor: '${resumoMes!.qtdVales}',
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (!mesFechado)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onFecharMes,
                      icon: const Icon(Icons.lock_clock, size: 18),
                      label: const Text('Fechar mes RH'),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onReabrirMes,
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('Reabrir mes'),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onExportarFolhaEquipe,
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('CSV folha equipe'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onExportarLancamentosAno,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('CSV lancamentos ano'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onRelatorioSetor,
                    icon: const Icon(Icons.pie_chart_outline, size: 18),
                    label: const Text('Folha por setor'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (historico12Meses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Historico 12 meses (liquido)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: historico12Meses.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final h = historico12Meses[i];
                return Container(
                  width: compact ? 88 : 96,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: h.fechado
                        ? semantic.successBg
                            .withValues(alpha: 0.65)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _mesCurto.format(h.mesReferencia),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _moedaPainel.format(h.liquidoApagar),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                      if (h.fechado)
                        Icon(
                          Icons.check_circle,
                          size: 12,
                          color: semantic.successFg,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricaFolha extends StatelessWidget {
  const _MetricaFolha({
    required this.rotulo,
    required this.valor,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
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
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: destaque ? FontWeight.w800 : FontWeight.w600,
            color: destaque ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}

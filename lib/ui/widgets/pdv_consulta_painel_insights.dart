import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/pdv_consulta_insights_service.dart';

final _dataCurta = DateFormat('dd/MM/yy');

/// Secao de insights premium (pacote 3) no painel lateral da consulta PDV.
class PdvConsultaPainelInsights extends StatelessWidget {
  const PdvConsultaPainelInsights({
    super.key,
    required this.insights,
    required this.formatarMoeda,
    this.onSelecionarSimilar,
    this.onInserirKit,
    this.onAdicionarAgregado,
  });

  final PdvConsultaInsightsPacote insights;
  final String Function(double) formatarMoeda;
  final ValueChanged<int>? onSelecionarSimilar;
  final ValueChanged<PdvConsultaKitResumo>? onInserirKit;
  final ValueChanged<PdvConsultaAgregadoVenda>? onAdicionarAgregado;

  @override
  Widget build(BuildContext context) {
    if (!insights.temConteudo) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Insights',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (insights.historicoCliente != null)
          _InsightCard(
            icon: Icons.history,
            iconColor: scheme.primary,
            titulo: 'Historico do cliente',
            child: _HistoricoClienteTexto(
              historico: insights.historicoCliente!,
            ),
          ),
        if (insights.alertaMargem != null) ...[
          if (insights.historicoCliente != null) const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.percent,
            iconColor: insights.alertaMargem!.abaixoMargemMinima ||
                    insights.alertaMargem!.abaixoCusto
                ? scheme.error
                : scheme.tertiary,
            titulo: 'Margem (gerente)',
            child: _MargemTexto(
              alerta: insights.alertaMargem!,
              formatarMoeda: formatarMoeda,
            ),
          ),
        ],
        if (insights.rotuloDeposito != null) ...[
          const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.warehouse_outlined,
            iconColor: scheme.secondary,
            titulo: 'Deposito / local',
            child: Text(
              insights.rotuloDeposito!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (insights.trechoAplicacao != null) ...[
          const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.engineering_outlined,
            iconColor: scheme.primary,
            titulo: 'Aplicacao / descricao',
            child: Text(
              insights.trechoAplicacao!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
        if (insights.similares.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.swap_horiz,
            iconColor: scheme.tertiary,
            titulo: 'Substitutos / similares',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < insights.similares.length; i++) ...[
                  if (i > 0) const Divider(height: 12),
                  _SimilarLinha(
                    similar: insights.similares[i],
                    formatarMoeda: formatarMoeda,
                    onTap: onSelecionarSimilar == null
                        ? null
                        : () => onSelecionarSimilar!(insights.similares[i].produtoId),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (insights.agregados.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.add_shopping_cart_outlined,
            iconColor: scheme.primary,
            titulo: 'Ofereca tambem',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < insights.agregados.length; i++) ...[
                  if (i > 0) const Divider(height: 8),
                  _AgregadoLinha(
                    agregado: insights.agregados[i],
                    formatarMoeda: formatarMoeda,
                    onAdicionar: onAdicionarAgregado == null
                        ? null
                        : () => onAdicionarAgregado!(insights.agregados[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (insights.kits.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InsightCard(
            icon: Icons.view_module_outlined,
            iconColor: scheme.secondary,
            titulo: 'Kits sugeridos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < insights.kits.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  Text(
                    insights.kits[i].nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${insights.kits[i].quantidadeItens} item(ns)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (onInserirKit != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () => onInserirKit!(insights.kits[i]),
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('Inserir kit'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AgregadoLinha extends StatelessWidget {
  const _AgregadoLinha({
    required this.agregado,
    required this.formatarMoeda,
    this.onAdicionar,
  });

  final PdvConsultaAgregadoVenda agregado;
  final String Function(double) formatarMoeda;
  final VoidCallback? onAdicionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final detalhe = agregado.detalheLinha(formatarMoeda);

    final conteudo = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                agregado.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                detalhe,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: agregado.semEstoque
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                  fontWeight: agregado.semEstoque ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
        if (onAdicionar != null)
          Icon(
            Icons.add,
            size: 18,
            color: scheme.primary.withValues(alpha: 0.85),
          ),
      ],
    );

    if (onAdicionar == null) return conteudo;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Adicionar ${agregado.quantidadeSugerida}',
        child: InkWell(
          onTap: onAdicionar,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: conteudo,
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.iconColor,
    required this.titulo,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _HistoricoClienteTexto extends StatelessWidget {
  const _HistoricoClienteTexto({required this.historico});

  final PdvConsultaHistoricoClienteProduto historico;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ultima = historico.ultimaCompraEm;
    return Text(
      '${historico.comprasNoPeriodo} compra(s) nos ultimos '
      '${historico.diasPeriodo} dias · '
      '${historico.quantidadeLiquida} un.'
      '${ultima != null ? ' · Ultima ${_dataCurta.format(ultima.toLocal())}' : ''}',
      style: theme.textTheme.bodySmall,
    );
  }
}

class _MargemTexto extends StatelessWidget {
  const _MargemTexto({
    required this.alerta,
    required this.formatarMoeda,
  });

  final PdvConsultaAlertaMargem alerta;
  final String Function(double) formatarMoeda;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cor = alerta.abaixoMargemMinima || alerta.abaixoCusto
        ? scheme.error
        : scheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Margem ${alerta.margemPercentual.toStringAsFixed(1)}% · '
          'Custo ${formatarMoeda(alerta.custoReferencia)} · '
          'Venda ${formatarMoeda(alerta.precoVenda)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (alerta.abaixoCusto) ...[
          const SizedBox(height: 4),
          Text(
            'Preco abaixo do custo!',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ] else if (alerta.abaixoMargemMinima) ...[
          const SizedBox(height: 4),
          Text(
            'Abaixo da margem minima '
            '(${alerta.margemMinimaReferencia.toStringAsFixed(0)}%)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _SimilarLinha extends StatelessWidget {
  const _SimilarLinha({
    required this.similar,
    required this.formatarMoeda,
    this.onTap,
  });

  final PdvConsultaProdutoSimilar similar;
  final String Function(double) formatarMoeda;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conteudo = Row(
      children: [
        if (similar.cadastrado) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Cad.',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            similar.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          similar.semEstoque
              ? 'Sem estoque · ${formatarMoeda(similar.precoReferencia)}'
              : '${similar.estoqueDisponivel} · ${formatarMoeda(similar.precoReferencia)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: similar.semEstoque
                ? scheme.error
                : scheme.onSurfaceVariant,
            fontWeight: similar.semEstoque ? FontWeight.w700 : null,
          ),
        ),
      ],
    );

    if (onTap == null) return conteudo;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: conteudo,
        ),
      ),
    );
  }
}

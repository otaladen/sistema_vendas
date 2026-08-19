import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ListagemVendasCabecalho extends StatelessWidget {
  const ListagemVendasCabecalho({
    super.key,
    required this.totalRegistros,
    required this.exibidos,
    required this.valorTotalExibido,
    required this.onAtualizar,
  });

  final int totalRegistros;
  final int exibidos;
  final double valorTotalExibido;
  final VoidCallback? onAtualizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final estreito = MediaQuery.sizeOf(context).width < 720;

    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listagem de vendas',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vendas finalizadas no caixa — consulta, fiscal e devolucoes.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final kpis = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Atualizar lista',
          onPressed: onAtualizar,
          icon: const Icon(Icons.refresh),
        ),
        _KpiTile(
          rotulo: 'Registros',
          valor: totalRegistros == 0 ? '0' : '$exibidos / $totalRegistros',
          icone: Icons.receipt_long_outlined,
        ),
        const SizedBox(width: 10),
        _KpiTile(
          rotulo: 'Total do filtro',
          valor: moeda.format(valorTotalExibido),
          icone: Icons.payments_outlined,
          destaque: true,
        ),
      ],
    );

    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: estreito
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titulo,
                  const SizedBox(height: 12),
                  kpis,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titulo),
                  kpis,
                ],
              ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.rotulo,
    required this.valor,
    required this.icone,
    this.destaque = false,
  });

  final String rotulo;
  final String valor;
  final IconData icone;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: destaque
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.12),
                scheme.surface,
              )
            : scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: destaque
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rotulo,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                valor,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

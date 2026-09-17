import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ListagemVendasCabecalho extends StatelessWidget {
  const ListagemVendasCabecalho({
    super.key,
    required this.totalRegistros,
    required this.exibidos,
    required this.valorTotalExibido,
    required this.filtroFiscal,
    required this.onFiltroFiscalRapido,
    required this.onAtualizar,
  });

  final int totalRegistros;
  final int exibidos;
  final double valorTotalExibido;
  final String filtroFiscal;
  final ValueChanged<String> onFiltroFiscalRapido;
  final VoidCallback? onAtualizar;

  static const _filtrosRapidos = <({String valor, String rotulo})>[
    (valor: 'todos', rotulo: 'Todas'),
    (valor: 'concluida_fiscal', rotulo: 'Concluídas'),
    (valor: 'fiscal_pendente', rotulo: 'Pendentes fiscais'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final estreito = MediaQuery.sizeOf(context).width < 900;

    final resumoRegistros = totalRegistros == 0
        ? '0'
        : '$exibidos / $totalRegistros';
    final resumoValor = moeda.format(valorTotalExibido);

    final kpis = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ResumoChip(
          icone: Icons.receipt_long_outlined,
          texto: 'Registros: $resumoRegistros',
        ),
        _ResumoChip(
          icone: Icons.payments_outlined,
          texto: 'Total: $resumoValor',
          destaque: true,
        ),
        IconButton(
          tooltip: 'Atualizar lista',
          visualDensity: VisualDensity.compact,
          onPressed: onAtualizar,
          icon: const Icon(Icons.refresh, size: 22),
        ),
      ],
    );

    final filtrosRapidos = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _filtrosRapidos.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _FiltroRapidoChip(
              rotulo: _filtrosRapidos[i].rotulo,
              selecionado: filtroFiscal == _filtrosRapidos[i].valor,
              onTap: () => onFiltroFiscalRapido(_filtrosRapidos[i].valor),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            estreito
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Listagem de vendas',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      kpis,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Listagem de vendas',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: kpis),
                    ],
                  ),
            const SizedBox(height: 8),
            filtrosRapidos,
          ],
        ),
      ),
    );
  }
}

class _ResumoChip extends StatelessWidget {
  const _ResumoChip({
    required this.icone,
    required this.texto,
    this.destaque = false,
  });

  final IconData icone;
  final String texto;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: destaque
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.1),
                scheme.surface,
              )
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: destaque
              ? scheme.primary.withValues(alpha: 0.28)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icone,
            size: 16,
            color: destaque ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltroRapidoChip extends StatelessWidget {
  const _FiltroRapidoChip({
    required this.rotulo,
    required this.selecionado,
    required this.onTap,
  });

  final String rotulo;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selecionado
          ? scheme.primaryContainer.withValues(alpha: 0.9)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            rotulo,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
              color: selecionado ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

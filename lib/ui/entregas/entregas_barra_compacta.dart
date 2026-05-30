import 'package:flutter/material.dart';

import 'planejamento_entrega_dia.dart';

/// Faixa compacta: resumo + planejamento + filtros + relatorios.
class EntregasBarraCompacta extends StatelessWidget {
  const EntregasBarraCompacta({
    super.key,
    required this.atrasadas,
    required this.pendentesHoje,
    required this.filtroAtrasadasAtivo,
    required this.filtroPendentesHojeAtivo,
    required this.onFiltroAtrasadas,
    required this.onFiltroPendentesHoje,
    required this.mostrarPlanejamento,
    required this.resumoPorDia,
    required this.chaveDiaSelecionada,
    required this.onSelecionarDia,
    required this.onAbrirSeletorDia,
    required this.filtrosAtivos,
    required this.onAbrirFiltros,
    required this.mostrarRelatorios,
    required this.onRelatorios,
    required this.mostrarProximosDias,
    required this.onAlternarProximosDias,
    required this.proximosDiasExpandido,
  });

  final int atrasadas;
  final int pendentesHoje;
  final bool filtroAtrasadasAtivo;
  final bool filtroPendentesHojeAtivo;
  final ValueChanged<bool> onFiltroAtrasadas;
  final ValueChanged<bool> onFiltroPendentesHoje;
  final bool mostrarPlanejamento;
  final Map<String, int> resumoPorDia;
  final String? chaveDiaSelecionada;
  final ValueChanged<String?> onSelecionarDia;
  final VoidCallback onAbrirSeletorDia;
  final int filtrosAtivos;
  final VoidCallback onAbrirFiltros;
  final bool mostrarRelatorios;
  final VoidCallback onRelatorios;
  final bool mostrarProximosDias;
  final VoidCallback onAlternarProximosDias;
  final bool proximosDiasExpandido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estreita = MediaQuery.sizeOf(context).width < 520;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          Icons.warning_amber_outlined,
                          size: 16,
                          color: atrasadas > 0
                              ? Colors.red.shade700
                              : Colors.grey,
                        ),
                        label: Text(
                          estreita ? '$atrasadas' : 'Atr. $atrasadas',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: filtroAtrasadasAtivo,
                        onSelected: onFiltroAtrasadas,
                      ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          Icons.today_outlined,
                          size: 16,
                          color: pendentesHoje > 0
                              ? theme.colorScheme.primary
                              : Colors.grey,
                        ),
                        label: Text(
                          estreita ? 'Hj $pendentesHoje' : 'Pend. hoje $pendentesHoje',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: filtroPendentesHojeAtivo,
                        onSelected: onFiltroPendentesHoje,
                      ),
                    ],
                  ),
                ),
                Badge(
                  isLabelVisible: filtrosAtivos > 0,
                  label: Text('$filtrosAtivos'),
                  child: IconButton(
                    tooltip: 'Filtros e periodo',
                    visualDensity: VisualDensity.compact,
                    onPressed: onAbrirFiltros,
                    icon: const Icon(Icons.tune_outlined),
                  ),
                ),
                if (mostrarRelatorios)
                  IconButton(
                    tooltip: 'Relatorios',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRelatorios,
                    icon: const Icon(Icons.summarize_outlined),
                  ),
              ],
            ),
            if (mostrarPlanejamento) ...[
              const SizedBox(height: 6),
              Text(
                'Dia da entrega',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              BarraPlanejamentoEntregaDia(
                resumoPorDia: resumoPorDia,
                chaveSelecionada: chaveDiaSelecionada,
                onSelecionar: onSelecionarDia,
                onAbrirSeletor: onAbrirSeletorDia,
              ),
            ],
            if (mostrarProximosDias) ...[
              const SizedBox(height: 2),
              InkWell(
                onTap: onAlternarProximosDias,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        proximosDiasExpandido
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        proximosDiasExpandido
                            ? 'Ocultar proximos dias'
                            : 'Proximos dias com entrega',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (proximosDiasExpandido)
                ProximosDiasPlanejamentoEntrega(
                  resumoPorDia: resumoPorDia,
                  chaveSelecionada: chaveDiaSelecionada,
                  onSelecionar: onSelecionarDia,
                  mostrarTitulo: false,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Botoes de agrupamento "mesmo carro" (so quando o modo esta ativo).
class EntregasBarraAgrupamentoMesmoCarro extends StatelessWidget {
  const EntregasBarraAgrupamentoMesmoCarro({
    super.key,
    required this.selecionadas,
    required this.onConfirmar,
    required this.onLimparSelecao,
    required this.onRemoverAgrupamento,
  });

  final int selecionadas;
  final VoidCallback? onConfirmar;
  final VoidCallback onLimparSelecao;
  final VoidCallback onRemoverAgrupamento;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(
            alpha: 0.35,
          ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            Text(
              'Mesmo carro · $selecionadas sel.',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            FilledButton.tonalIcon(
              onPressed: onConfirmar,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Confirmar'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            TextButton(
              onPressed: onLimparSelecao,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Limpar'),
            ),
            TextButton(
              onPressed: onRemoverAgrupamento,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Tirar agrup.'),
            ),
          ],
        ),
      ),
    );
  }
}

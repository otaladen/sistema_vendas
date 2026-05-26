import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/fiscal/nfe_historico_filtro.dart';

/// Barra de filtros da aba Historico NF-e.
class NfeHistoricoFiltrosBar extends StatelessWidget {
  const NfeHistoricoFiltrosBar({
    super.key,
    required this.filtro,
    required this.buscaController,
    required this.totalRegistros,
    required this.totalFiltrados,
    required this.onFiltroChanged,
    required this.onLimparPeriodo,
    required this.onEscolherPeriodo,
  });

  final NfeHistoricoFiltro filtro;
  final TextEditingController buscaController;
  final int totalRegistros;
  final int totalFiltrados;
  final ValueChanged<NfeHistoricoFiltro> onFiltroChanged;
  final VoidCallback onLimparPeriodo;
  final VoidCallback onEscolherPeriodo;

  static final _dataFmt = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodo = _rotuloPeriodo(filtro.dataInicio, filtro.dataFim);

    return Material(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: buscaController,
              decoration: InputDecoration(
                hintText: 'Cliente, orcamento, chave, referencia...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: buscaController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          buscaController.clear();
                          onFiltroChanged(
                            NfeHistoricoFiltro(
                              textoBusca: '',
                              status: filtro.status,
                              dataInicio: filtro.dataInicio,
                              dataFim: filtro.dataFim,
                            ),
                          );
                        },
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => onFiltroChanged(
                NfeHistoricoFiltro(
                  textoBusca: v,
                  status: filtro.status,
                  dataInicio: filtro.dataInicio,
                  dataFim: filtro.dataFim,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in NfeHistoricoStatusFiltro.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(s.rotulo),
                        selected: filtro.status == s,
                        onSelected: (_) => onFiltroChanged(
                          NfeHistoricoFiltro(
                            textoBusca: filtro.textoBusca,
                            status: s,
                            dataInicio: filtro.dataInicio,
                            dataFim: filtro.dataFim,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onEscolherPeriodo,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(periodo),
                ),
                if (filtro.dataInicio != null || filtro.dataFim != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Limpar periodo',
                    onPressed: onLimparPeriodo,
                    icon: const Icon(Icons.event_busy_outlined),
                  ),
                ],
                const Spacer(),
                Text(
                  '$totalFiltrados de $totalRegistros',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _rotuloPeriodo(DateTime? inicio, DateTime? fim) {
    if (inicio == null && fim == null) return 'Periodo: todos';
    if (inicio != null && fim != null) {
      return '${_dataFmt.format(inicio)} — ${_dataFmt.format(fim)}';
    }
    if (inicio != null) return 'A partir de ${_dataFmt.format(inicio)}';
    return 'Ate ${_dataFmt.format(fim!)}';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/api/venda_api_repository.dart';
import '../relatorio_helpers.dart';
import '../relatorio_periodo.dart';

/// Painel superior padrao: periodo + resumo opcional + area de filtros extras.
class RelatorioPeriodoPainel extends StatefulWidget {
  const RelatorioPeriodoPainel({
    super.key,
    required this.onPeriodoChanged,
    this.vendaRepository,
    this.filtrosExtras = const [],
    this.resumo,
    this.onAtualizar,
    this.labelPeriodo = 'Periodo',
  });

  final void Function(LimitesPeriodo limites) onPeriodoChanged;
  final dynamic vendaRepository;
  final List<Widget> filtrosExtras;
  final Widget? resumo;
  final VoidCallback? onAtualizar;
  final String labelPeriodo;

  @override
  State<RelatorioPeriodoPainel> createState() => _RelatorioPeriodoPainelState();
}

class _RelatorioPeriodoPainelState extends State<RelatorioPeriodoPainel> {
  bool _hidratando = false;
  bool _janelaTruncada = false;

  Future<void> _emitir(LimitesPeriodo limites) async {
    if (widget.vendaRepository is VendaApiRepository) {
      if (mounted) setState(() => _hidratando = true);
      await relatorioHidratarPeriodoApi(widget.vendaRepository, limites);
      final truncada = (widget.vendaRepository as VendaApiRepository)
          .relatorioJanelaTruncada;
      if (mounted) {
        setState(() {
          _hidratando = false;
          _janelaTruncada = truncada;
        });
      }
    }
    if (!mounted) return;
    widget.onPeriodoChanged(limites);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RelatorioSeletorPeriodo(
                    label: widget.labelPeriodo,
                    onChanged: (lim) => unawaited(_emitir(lim)),
                  ),
                ),
                if (widget.onAtualizar != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: _hidratando ? null : widget.onAtualizar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
            if (_hidratando) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 4),
              Text(
                'Baixando vendas do periodo no servidor...',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (_janelaTruncada) ...[
              const SizedBox(height: 8),
              Text(
                'Periodo grande demais no terminal: o relatorio pode estar '
                'incompleto. Confira no PC servidor ou encurte o intervalo.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (widget.filtrosExtras.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...widget.filtrosExtras,
            ],
            if (widget.resumo != null) ...[
              const SizedBox(height: 8),
              widget.resumo!,
            ],
          ],
        ),
      ),
    );
  }
}

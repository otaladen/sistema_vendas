import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../model/venda.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioEntregasResumoPage extends StatefulWidget {
  const RelatorioEntregasResumoPage({
    super.key,
    required this.vendaRepository,
    this.clienteRepository,
    this.onAbrirModuloEntregas,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final VoidCallback? onAbrirModuloEntregas;

  @override
  State<RelatorioEntregasResumoPage> createState() =>
      _RelatorioEntregasResumoPageState();
}

class _RelatorioEntregasResumoPageState extends State<RelatorioEntregasResumoPage> {
  final _fmtData = DateFormat('dd/MM/yyyy');
  final _fmtMoeda = NumberFormat('#,##0.00', 'pt_BR');
  List<Venda> _entregas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        await repo.hidratarEntregas(limit: 500);
      } catch (_) {}
    }
    final lista = (repo.listarEntregas() as List).cast<Venda>();
    lista.sort((a, b) {
      final aa = relatorioEntregaEhAtrasada(a);
      final ab = relatorioEntregaEhAtrasada(b);
      if (aa != ab) return aa ? -1 : 1;
      return b.data.compareTo(a.data);
    });
    if (!mounted) return;
    setState(() => _entregas = lista);
  }

  String _nomeCliente(Venda v) => relatorioNomeCliente(
        v,
        clienteRepository: widget.clienteRepository,
      );

  Map<String, int> _porStatus() {
    final m = <String, int>{};
    for (final v in _entregas) {
      final s = v.statusEntrega;
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }

  List<List<String>> _linhasCsv() => [
        ['Nota', 'Cliente', 'Status', 'Data marcada', 'Total'],
        ..._entregas.map((v) {
          final cli = _nomeCliente(v);
          final dm = v.dataEntregaMarcada;
          return [
            '${v.numeroOrcamento}',
            cli,
            v.statusEntrega,
            dm != null ? _fmtData.format(dm.toLocal()) : '',
            _fmtMoeda.format(v.total),
          ];
        }),
      ];

  List<String> _paginasPdf() {
    return relatorioMontarPaginasTabela(
      titulo: 'RESUMO ENTREGAS',
      subtitulo: '${_entregas.length} pedido(s) com carreto',
      cabecalho: ['Nota', 'Status', 'Data marc.', 'Cliente'],
      linhas: _entregas
          .take(200)
          .map(
            (v) => [
              '${v.numeroOrcamento}',
              relatorioRotuloStatusEntrega(v.statusEntrega),
              v.dataEntregaMarcada != null
                  ? _fmtData.format(v.dataEntregaMarcada!.toLocal())
                  : '-',
              _nomeCliente(v),
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final atrasadas = _entregas.where(relatorioEntregaEhAtrasada).length;
    final hoje = _entregas.where(relatorioEntregaEhAgendaHoje).length;
    final porStatus = _porStatus();
    final abrir = widget.onAbrirModuloEntregas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas — resumo'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'entregas_resumo',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _chipResumo(
                        context,
                        'Atrasadas',
                        '$atrasadas',
                        Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chipResumo(
                        context,
                        'Para hoje',
                        '$hoje',
                        Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chipResumo(
                        context,
                        'Total',
                        '${_entregas.length}',
                        Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: porStatus.entries.map((e) {
                    return Chip(
                      label: Text(
                        '${relatorioRotuloStatusEntrega(e.key)}: ${e.value}',
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                if (abrir != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: abrir,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Abrir modulo Entregas (romaneios)'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _entregas.isEmpty
                ? const Center(child: Text('Nenhuma entrega com carreto.'))
                : ListView.builder(
                    itemCount: _entregas.length,
                    itemBuilder: (context, i) {
                      final v = _entregas[i];
                      final atrasada = relatorioEntregaEhAtrasada(v);
                      final dm = v.dataEntregaMarcada;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          atrasada
                              ? Icons.warning_amber
                              : Icons.local_shipping_outlined,
                          color: atrasada
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(
                          'Ped. ${v.numeroOrcamento} · ${_nomeCliente(v)}',
                        ),
                        subtitle: Text(
                          '${relatorioRotuloStatusEntrega(v.statusEntrega)} · '
                          '${dm != null ? _fmtData.format(dm.toLocal()) : 'Sem data'} · '
                          'R\$ ${_fmtMoeda.format(v.total)}',
                        ),
                        onTap: () => mostrarDetalheVendaRelatorio(
                          context,
                          vendaRepository: widget.vendaRepository,
                          vendaId: v.id,
                          clienteRepository: widget.clienteRepository,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chipResumo(
    BuildContext context,
    String rotulo,
    String valor,
    Color cor,
  ) {
    return Card(
      elevation: 0,
      color: cor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          children: [
            Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
            Text(
              valor,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

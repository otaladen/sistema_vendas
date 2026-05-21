import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioOrcamentosAbertosPage extends StatefulWidget {
  const RelatorioOrcamentosAbertosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;

  @override
  State<RelatorioOrcamentosAbertosPage> createState() =>
      _RelatorioOrcamentosAbertosPageState();
}

class _RelatorioOrcamentosAbertosPageState
    extends State<RelatorioOrcamentosAbertosPage> {
  List<Venda> _orcs = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    setState(() {
      _orcs = widget.vendaRepository.listarOrcamentosPendentes()
        ..sort((a, b) => b.data.compareTo(a.data));
    });
  }

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  int _diasAberto(Venda v) {
    final hoje = DateTime.now();
    final d = v.data.toLocal();
    final ref = DateTime(hoje.year, hoje.month, hoje.day);
    final vd = DateTime(d.year, d.month, d.day);
    return ref.difference(vd).inDays;
  }

  List<List<String>> _linhasCsv() {
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return [
      ['Orcamento', 'Data', 'Cliente', 'Dias aberto', 'Itens', 'Total'],
      ..._orcs.map((v) {
        final c = _cliente(v);
        return [
          '${v.numeroOrcamento}',
          DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal()),
          c?.nomeRazao ?? 'Sem cliente',
          '${_diasAberto(v)}',
          '${v.itens.length}',
          moeda.format(v.total),
        ];
      }),
    ];
  }

  List<String> _paginasPdf() {
    final total = _orcs.fold<double>(0, (s, v) => s + v.total);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    return relatorioMontarPaginasTabela(
      titulo: 'ORCAMENTOS EM ABERTO',
      subtitulo:
          '${_orcs.length} orcamento(s) · Total R\$ ${moeda.format(total)}',
      cabecalho: ['Orc', 'Data', 'Cliente', 'Dias', 'Total'],
      linhas: _orcs.map((v) {
        final c = _cliente(v);
        return [
          '${v.numeroOrcamento}',
          DateFormat('dd/MM/yyyy').format(v.data.toLocal()),
          c?.nomeRazao ?? '-',
          '${_diasAberto(v)}',
          'R\$ ${moeda.format(v.total)}',
        ];
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final NumberFormat moeda = NumberFormat('#,##0.00', 'pt_BR');
    String fmt(double v) => 'R\$ ${moeda.format(v)}';
    final total = _orcs.fold<double>(0, (s, v) => s + v.total);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orcamentos em aberto'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'orcamentos_abertos',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_orcs.length} orcamento(s) · Valor total ${fmt(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _orcs.isEmpty
                ? const Center(child: Text('Nenhum orcamento pendente.'))
                : ListView.builder(
                    itemCount: _orcs.length,
                    itemBuilder: (context, i) {
                      final v = _orcs[i];
                      final c = _cliente(v);
                      final dias = _diasAberto(v);
                      return ListTile(
                        title: Text(
                          'Orc. ${v.numeroOrcamento} · ${fmt(v.total)}',
                        ),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(v.data.toLocal())} · '
                          '${c?.nomeRazao ?? 'Sem cliente'} · '
                          '${v.itens.length} item(ns) · $dias dia(s) em aberto',
                        ),
                        trailing: dias >= 7
                            ? Chip(
                                label: Text('$dias d'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    Theme.of(context).colorScheme.errorContainer,
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => mostrarDetalheVendaRelatorio(
                          context,
                          vendaRepository: widget.vendaRepository,
                          vendaId: v.id,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/cliente.dart';
import '../../model/venda.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class _LinhaCliente {
  _LinhaCliente({
    required this.clienteId,
    required this.nome,
    required this.qtd,
    required this.total,
    required this.lucro,
  });

  final int clienteId;
  final String nome;
  final int qtd;
  final double total;
  final double lucro;

  double get margemPct =>
      total.abs() < 0.01 ? 0 : (lucro / total) * 100;
}

class RelatorioTopClientesPage extends StatefulWidget {
  const RelatorioTopClientesPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;

  @override
  State<RelatorioTopClientesPage> createState() => _RelatorioTopClientesPageState();
}

class _RelatorioTopClientesPageState extends State<RelatorioTopClientesPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  List<_LinhaCliente> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  Cliente? _cliente(Venda v) {
    final t = v.cliente.target;
    if (t != null) return t;
    final id = v.cliente.targetId;
    if (id == 0) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  void _calcular(LimitesPeriodo limites) {
    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, _LinhaCliente>{};
    for (final v in vendas) {
      final id = v.cliente.targetId;
      final c = _cliente(v);
      final nome = id == 0
          ? 'Sem cliente'
          : (c?.nomeRazao.trim().isNotEmpty == true
              ? c!.nomeRazao.trim()
              : 'Cliente #$id');
      final cur = map[id];
      if (cur == null) {
        map[id] = _LinhaCliente(
          clienteId: id,
          nome: nome,
          qtd: 1,
          total: v.total,
          lucro: v.lucroTotal,
        );
      } else {
        map[id] = _LinhaCliente(
          clienteId: id,
          nome: cur.nome,
          qtd: cur.qtd + 1,
          total: cur.total + v.total,
          lucro: cur.lucro + v.lucroTotal,
        );
      }
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(relatorioPeriodoFiltro(limites));
    for (final e in imp.porClienteFaturamento.entries) {
      final id = e.key;
      final adj = e.value;
      if (adj.abs() < 0.0001) continue;
      final cli = id == 0 ? null : widget.clienteRepository.obterPorId(id);
      final nomeFallback = id == 0
          ? 'Sem cliente'
          : (cli?.nomeRazao.trim().isNotEmpty == true
              ? cli!.nomeRazao.trim()
              : 'Cliente #$id');
      final cur = map[id];
      if (cur == null) {
        map[id] = _LinhaCliente(
          clienteId: id,
          nome: nomeFallback,
          qtd: 0,
          total: adj,
          lucro: 0,
        );
      } else {
        map[id] = _LinhaCliente(
          clienteId: id,
          nome: cur.nome,
          qtd: cur.qtd,
          total: cur.total + adj,
          lucro: cur.lucro,
        );
      }
    }
    final lista = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    setState(() {
      _limites = limites;
      _linhas = lista;
    });
  }

  RelatorioTotaisPeriodo? get _totaisAtual => _limites == null
      ? null
      : relatorioTotaisPeriodo(widget.vendaRepository, _limites!);

  RelatorioTotaisPeriodo? get _totaisAnterior {
    if (!_compararPeriodo || _limites == null) return null;
    return relatorioTotaisPeriodo(
      widget.vendaRepository,
      relatorioPeriodoAnterior(_limites!),
    );
  }

  List<List<String>> _linhasCsv() => [
        ['#', 'Cliente', 'Pedidos', 'Total', 'Lucro', 'Margem %'],
        ..._linhas.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nome,
                '${e.value.qtd}',
                _moeda.format(e.value.total),
                _moeda.format(e.value.lucro),
                e.value.margemPct.toStringAsFixed(1),
              ],
            ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'CLIENTES QUE MAIS COMPRARAM',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['#', 'Cliente', 'Pedidos', 'Total', 'Lucro'],
      linhas: _linhas.asMap().entries.map((e) {
        final r = e.value;
        return [
          '${e.key + 1}',
          r.nome,
          '${r.qtd}',
          _fmt(r.total),
          _fmt(r.lucro),
        ];
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final t = _totaisAtual;
    final periodoAnt =
        lim != null && _compararPeriodo ? relatorioPeriodoAnterior(lim) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes que mais compraram'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'top_clientes',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: _calcular,
            onAtualizar: lim != null ? () => _calcular(lim) : null,
            filtrosExtras: [
              if (lim != null)
                RelatorioSwitchComparativo(
                  value: _compararPeriodo,
                  periodoAnterior: periodoAnt,
                  onChanged: (v) => setState(() => _compararPeriodo = v),
                ),
            ],
            resumo: t == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (lim != null)
                        Text(
                          formatarIntervaloPeriodo(lim),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      const SizedBox(height: 8),
                      RelatorioKpiComparativo(
                        atual: t,
                        anterior: _totaisAnterior,
                        formatarMoeda: _fmt,
                        mostrarComparativo: _compararPeriodo,
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma venda no periodo.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final r = _linhas[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(r.nome),
                        subtitle: Text(
                          '${r.qtd} pedido(s) · ${_fmt(r.total)} · '
                          'Lucro ${_fmt(r.lucro)} · '
                          '${r.margemPct.toStringAsFixed(1)}%',
                        ),
                        trailing: r.clienteId > 0
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: r.clienteId > 0
                            ? () => mostrarResumoClienteRelatorio(
                                  context,
                                  clienteRepository: widget.clienteRepository,
                                  vendaRepository: widget.vendaRepository,
                                  clienteId: r.clienteId,
                                )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

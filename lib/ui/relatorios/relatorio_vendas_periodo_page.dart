import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../model/cliente.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioVendasPeriodoPage extends StatefulWidget {
  const RelatorioVendasPeriodoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic vendedorRepository;

  @override
  State<RelatorioVendasPeriodoPage> createState() =>
      _RelatorioVendasPeriodoPageState();
}

class _RelatorioVendasPeriodoPageState extends State<RelatorioVendasPeriodoPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final DateFormat _dh = DateFormat('dd/MM/yyyy HH:mm');
  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  List<RelatorioVendaLinhaLiquida> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  Cliente? _cliente(Venda v) => relatorioClienteDaVenda(
        v,
        clienteRepository: widget.clienteRepository,
      );

  Vendedor? _vendedor(Venda v) => relatorioVendedorDaVenda(
        v,
        vendedorRepository: widget.vendedorRepository,
      );

  String _nomeVendedor(Venda v) {
    final w = _vendedor(v);
    if (w == null) return '-';
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
    return n;
  }

  void _atualizar(LimitesPeriodo limites) {
    setState(() {
      _limites = limites;
      _linhas = relatorioVendasPeriodoLiquidas(widget.vendaRepository, limites);
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

  List<List<String>> _linhasCsv() {
    return [
      [
        'Nota',
        'Data',
        'Cliente',
        'Vendedor',
        'Pagamento',
        'Total',
        'Lucro',
        'Margem %',
      ],
      ..._linhas.map((l) {
        final v = l.venda;
        final c = _cliente(v);
        final margem = l.total.abs() < 0.01
            ? ''
            : ((l.lucro / l.total) * 100).toStringAsFixed(1);
        return [
          '${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
          _dh.format(v.data.toLocal()),
          c?.nomeRazao ?? 'Sem cliente',
          _nomeVendedor(v),
          relatorioRotuloFormaPagamento(v.formaPagamento),
          _moeda.format(l.total),
          _moeda.format(l.lucro),
          margem,
        ];
      }),
    ];
  }

  List<String> _paginasPdf() {
    final t = _totaisAtual;
    if (_limites == null || t == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'VENDAS POR PERIODO',
      subtitulo:
          '${formatarIntervaloPeriodo(_limites!)} · '
          '${t.qtdNotas} nota(s) · Fat. ${_fmt(t.faturamento)} · '
          'Lucro ${_fmt(t.lucro)}',
      cabecalho: [
        'Nota',
        'Data',
        'Cliente',
        'Total',
        'Lucro',
      ],
      linhas: _linhas
          .map(
            (l) => [
              '${l.venda.numeroOrcamento > 0 ? l.venda.numeroOrcamento : l.venda.id}',
              DateFormat('dd/MM/yyyy').format(l.venda.data.toLocal()),
              _cliente(l.venda)?.nomeRazao ?? '-',
              _fmt(l.total),
              _fmt(l.lucro),
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _totaisAtual;
    final lim = _limites;
    final ant = _totaisAnterior;
    final periodoAnt =
        lim != null && _compararPeriodo ? relatorioPeriodoAnterior(lim) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas por periodo'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'vendas_periodo',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: _atualizar,
            onAtualizar: lim != null ? () => _atualizar(lim) : null,
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
                      Text(
                        formatarIntervaloPeriodo(lim!),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      RelatorioKpiComparativo(
                        atual: t,
                        anterior: ant,
                        formatarMoeda: _fmt,
                        mostrarComparativo: _compararPeriodo,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Valores liquidos de devolucao/troca do periodo. '
                        'Margem ${t.margemPct.toStringAsFixed(1)}% · '
                        'Ticket medio ${_fmt(t.ticketMedio)} · '
                        'Toque na linha para detalhes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhuma venda finalizada neste periodo.'))
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final l = _linhas[i];
                      final v = l.venda;
                      final c = _cliente(v);
                      final margem = l.total.abs() < 0.01
                          ? 0.0
                          : (l.lucro / l.total) * 100;
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id} · '
                          '${_fmt(l.total)} · Lucro ${_fmt(l.lucro)}'
                          '${l.teveAjuste ? ' (liq.)' : ''}',
                        ),
                        subtitle: Text(
                          '${_dh.format(v.data.toLocal())} · '
                          '${c?.nomeRazao ?? 'Sem cliente'} · '
                          '${_nomeVendedor(v)} · '
                          '${margem.toStringAsFixed(1)}% margem',
                          maxLines: 2,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => mostrarDetalheVendaRelatorio(
                          context,
                          vendaRepository: widget.vendaRepository,
                          vendaId: v.id,
                          clienteRepository: widget.clienteRepository,
                        ),
                        onLongPress: c != null && c.id > 0
                            ? () => mostrarResumoClienteRelatorio(
                                  context,
                                  clienteRepository: widget.clienteRepository,
                                  vendaRepository: widget.vendaRepository,
                                  clienteId: c.id,
                                  vendedorRepository: widget.vendedorRepository,
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

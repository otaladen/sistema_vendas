import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../model/vendedor.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioVendasPorVendedorPage extends StatefulWidget {
  const RelatorioVendasPorVendedorPage({
    super.key,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;

  @override
  State<RelatorioVendasPorVendedorPage> createState() =>
      _RelatorioVendasPorVendedorPageState();
}

class _LinhaVendedor {
  _LinhaVendedor({
    required this.vendedorId,
    required this.nome,
    required this.qtd,
    required this.total,
    required this.lucro,
    this.vendedor,
  });

  final int vendedorId;
  final String nome;
  final int qtd;
  final double total;
  final double lucro;
  final Vendedor? vendedor;

  double get margemPct =>
      total.abs() < 0.01 ? 0 : (lucro / total) * 100;
}

class _RelatorioVendasPorVendedorPageState
    extends State<RelatorioVendasPorVendedorPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  List<_LinhaVendedor> _linhas = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  String _nome(Vendedor? w) {
    if (w == null) return 'Sem vendedor';
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto;
    return n;
  }

  void _calcular(LimitesPeriodo limites) {
    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, _LinhaVendedor>{};
    for (final v in vendas) {
      final id = v.vendedor.targetId;
      final w = v.vendedor.target ?? widget.vendedorRepository.obterPorId(id);
      final nome = _nome(w);
      final cur = map[id];
      if (cur == null) {
        map[id] = _LinhaVendedor(
          vendedorId: id,
          nome: nome,
          qtd: 1,
          total: v.total,
          lucro: v.lucroTotal,
          vendedor: w,
        );
      } else {
        map[id] = _LinhaVendedor(
          vendedorId: id,
          nome: cur.nome,
          qtd: cur.qtd + 1,
          total: cur.total + v.total,
          lucro: cur.lucro + v.lucroTotal,
          vendedor: w ?? cur.vendedor,
        );
      }
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(relatorioPeriodoFiltro(limites));
    for (final e in imp.porVendedorFaturamento.entries) {
      final id = e.key;
      final adjFat = e.value;
      final adjLuc = imp.porVendedorLucro[id] ?? 0;
      if (adjFat.abs() < 0.0001 && adjLuc.abs() < 0.0001) continue;
      final w = id == 0 ? null : widget.vendedorRepository.obterPorId(id);
      final nome = _nome(w);
      final cur = map[id];
      if (cur == null) {
        map[id] = _LinhaVendedor(
          vendedorId: id,
          nome: nome,
          qtd: 0,
          total: adjFat,
          lucro: adjLuc,
          vendedor: w,
        );
      } else {
        map[id] = _LinhaVendedor(
          vendedorId: id,
          nome: cur.nome,
          qtd: cur.qtd,
          total: cur.total + adjFat,
          lucro: cur.lucro + adjLuc,
          vendedor: cur.vendedor,
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
        [
          '#',
          'Vendedor',
          'Vendas',
          'Faturamento',
          'Lucro',
          'Margem %',
          'Meta mensal',
        ],
        ..._linhas.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nome,
                '${e.value.qtd}',
                _moeda.format(e.value.total),
                _moeda.format(e.value.lucro),
                e.value.margemPct.toStringAsFixed(1),
                e.value.vendedor != null && e.value.vendedor!.metaMensalValor > 0
                    ? _moeda.format(e.value.vendedor!.metaMensalValor)
                    : '',
              ],
            ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'VENDAS POR VENDEDOR',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['#', 'Vendedor', 'Vendas', 'Total', 'Lucro', 'Margem%'],
      linhas: _linhas.asMap().entries.map((e) {
        final r = e.value;
        return [
          '${e.key + 1}',
          r.nome,
          '${r.qtd}',
          _fmt(r.total),
          _fmt(r.lucro),
          r.margemPct.toStringAsFixed(1),
        ];
      }).toList(),
    );
  }

  Future<void> _detalheVendedor(_LinhaVendedor r) async {
    if (_limites == null) return;
    final vendas = relatorioVendasFinalizadasPeriodo(
      widget.vendaRepository,
      _limites!,
    ).where((v) => v.vendedor.targetId == r.vendedorId).toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.nome),
        content: SizedBox(
          width: 400,
          height: 320,
          child: vendas.isEmpty
              ? const Text('Nenhuma venda no periodo.')
              : ListView.builder(
                  itemCount: vendas.length,
                  itemBuilder: (_, i) {
                    final v = vendas[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        'Nota ${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
                      ),
                      subtitle: Text('Lucro ${_fmt(v.lucroTotal)}'),
                      trailing: Text(_fmt(v.total)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
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
        title: const Text('Vendas por vendedor'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'vendas_por_vendedor',
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
                      final w = r.vendedor;
                      final meta = w?.metaMensalValor ?? 0;
                      final ating = meta > 0 ? (r.total / meta).clamp(0.0, 1.5) : null;
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(r.nome),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.qtd} venda(s) · ${_fmt(r.total)} · '
                              'Lucro ${_fmt(r.lucro)} · '
                              '${r.margemPct.toStringAsFixed(1)}%',
                            ),
                            if (ating != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: LinearProgressIndicator(
                                  value: ating > 1 ? 1 : ating,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            if (meta > 0)
                              Text(
                                'Meta ${_fmt(meta)} · '
                                '${(ating! * 100).toStringAsFixed(0)}% no periodo',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        isThreeLine: meta > 0,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _detalheVendedor(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

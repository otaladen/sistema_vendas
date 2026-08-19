import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../model/vendedor.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class _AggComissaoVendedor {
  _AggComissaoVendedor({required this.vendedorId});

  final int vendedorId;
  int quantidadeVendas = 0;
  double baseAcumulada = 0;
}

class RelatorioComissaoVendedoresPage extends StatefulWidget {
  const RelatorioComissaoVendedoresPage({
    super.key,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final dynamic vendaRepository;
  final dynamic vendedorRepository;

  @override
  State<RelatorioComissaoVendedoresPage> createState() =>
      _RelatorioComissaoVendedoresPageState();
}

class _RelatorioComissaoVendedoresPageState extends State<RelatorioComissaoVendedoresPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _pctFmt = NumberFormat('#0.##', 'pt_BR');

  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  /// `venda` = percentual sobre soma do valor da venda; `lucro` = sobre soma do lucro.
  String _baseCalculo = 'venda';
  bool _somenteVendedoresAtivos = false;
  int? _filtroVendedorId;

  List<({
    int vendedorId,
    Vendedor? vendedor,
    String nomeExibicao,
    int qtd,
    double base,
    double pct,
    double comissao,
    bool inativo,
  })> _linhas = [];

  double _totalBase = 0;
  double _totalComissao = 0;

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  String _nomeVendedor(Vendedor? w, int id) {
    if (w == null) {
      return id == 0 ? 'Sem vendedor' : 'Vendedor #$id';
    }
    final n = w.apelido.trim().isNotEmpty ? w.apelido.trim() : w.nomeCompleto.trim();
    final cod = w.codigoInterno.trim();
    return cod.isEmpty ? n : '$cod · $n';
  }

  void _recalcular() {
    final limites = _limites;
    if (limites == null) return;

    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, _AggComissaoVendedor>{};

    for (final v in vendas) {
      final id = v.vendedor.targetId;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;

      final Vendedor? w = id == 0
          ? null
          : relatorioVendedorDaVenda(
              v,
              vendedorRepository: widget.vendedorRepository,
            );
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }

      final parcelaBase = _baseCalculo == 'lucro' ? v.lucroTotal : v.total;
      map.putIfAbsent(id, () => _AggComissaoVendedor(vendedorId: id));
      final a = map[id]!;
      a.quantidadeVendas += 1;
      a.baseAcumulada += parcelaBase;
    }

    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(relatorioPeriodoFiltro(limites));
    final porVend = _baseCalculo == 'lucro'
        ? imp.porVendedorLucro
        : imp.porVendedorFaturamento;
    for (final e in porVend.entries) {
      final id = e.key;
      final adj = e.value;
      if (adj.abs() < 0.0001) continue;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;

      final Vendedor? w =
          id == 0 ? null : widget.vendedorRepository.obterPorId(id) as Vendedor?;
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }

      map.putIfAbsent(id, () => _AggComissaoVendedor(vendedorId: id));
      map[id]!.baseAcumulada += adj;
    }

    final saida =
        <({
          int vendedorId,
          Vendedor? vendedor,
          String nomeExibicao,
          int qtd,
          double base,
          double pct,
          double comissao,
          bool inativo,
        })>[];

    var sumBase = 0.0;
    var sumCom = 0.0;

    for (final e in map.entries) {
      final id = e.key;
      final agg = e.value;
      final Vendedor? w =
          id == 0 ? null : widget.vendedorRepository.obterPorId(id) as Vendedor?;
      final pct = w?.percentualComissao ?? 0;
      final comissao = relatorioComissaoPisoZero(agg.baseAcumulada, pct);
      final inativo = w != null && !w.ativo;
      saida.add((
        vendedorId: id,
        vendedor: w,
        nomeExibicao: _nomeVendedor(w, id),
        qtd: agg.quantidadeVendas,
        base: agg.baseAcumulada,
        pct: pct,
        comissao: comissao,
        inativo: inativo,
      ));
      sumBase += agg.baseAcumulada;
      sumCom += comissao;
    }

    saida.sort((a, b) => b.comissao.compareTo(a.comissao));

    setState(() {
      _linhas = saida;
      _totalBase = sumBase;
      _totalComissao = sumCom;
    });
  }

  void _onPeriodo(LimitesPeriodo limites) {
    setState(() => _limites = limites);
    _recalcular();
  }

  double _calcularComissaoTotalPeriodo(LimitesPeriodo limites) {
    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    final map = <int, double>{};
    for (final v in vendas) {
      final id = v.vendedor.targetId;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;
      final Vendedor? w =
          id == 0 ? null : widget.vendedorRepository.obterPorId(id) as Vendedor?;
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }
      final parcela = _baseCalculo == 'lucro' ? v.lucroTotal : v.total;
      map[id] = (map[id] ?? 0) + parcela;
    }
    final imp = widget.vendaRepository
        .calcularImpactosDevolucaoTrocaPeriodo(relatorioPeriodoFiltro(limites));
    final porVend = _baseCalculo == 'lucro'
        ? imp.porVendedorLucro
        : imp.porVendedorFaturamento;
    for (final e in porVend.entries) {
      final id = e.key;
      if (_filtroVendedorId != null && id != _filtroVendedorId) continue;
      final Vendedor? w =
          id == 0 ? null : widget.vendedorRepository.obterPorId(id) as Vendedor?;
      if (_somenteVendedoresAtivos && id != 0 && (w == null || !w.ativo)) {
        continue;
      }
      map[id] = (map[id] ?? 0) + e.value;
    }
    var total = 0.0;
    for (final e in map.entries) {
      final Vendedor? w = e.key == 0
          ? null
          : widget.vendedorRepository.obterPorId(e.key) as Vendedor?;
      final pct = w?.percentualComissao ?? 0;
      total += relatorioComissaoPisoZero(e.value, pct);
    }
    return total;
  }

  List<List<String>> _linhasCsv() => [
        [
          '#',
          'Vendedor',
          'Vendas',
          'Base',
          'Percentual',
          'Comissao',
        ],
        ..._linhas.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nomeExibicao,
                '${e.value.qtd}',
                _moeda.format(e.value.base),
                _pctFmt.format(e.value.pct),
                _moeda.format(e.value.comissao),
              ],
            ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'COMISSAO DE VENDEDORES',
      subtitulo:
          '${formatarIntervaloPeriodo(_limites!)} · Base $_baseCalculo · '
          'Total comissoes ${_fmt(_totalComissao)}',
      cabecalho: ['#', 'Vendedor', 'Vendas', 'Base', '%', 'Comissao'],
      linhas: _linhas.asMap().entries.map((e) {
        final r = e.value;
        return [
          '${e.key + 1}',
          r.nomeExibicao,
          '${r.qtd}',
          _fmt(r.base),
          '${_pctFmt.format(r.pct)}%',
          _fmt(r.comissao),
        ];
      }).toList(),
    );
  }

  Future<void> _detalheComissaoVendedor(
    int vendedorId,
    String nome,
  ) async {
    final lim = _limites;
    if (lim == null) return;
    final vendas = relatorioVendasFinalizadasPeriodo(
      widget.vendaRepository,
      lim,
    ).where((v) => v.vendedor.targetId == vendedorId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(nome),
        content: SizedBox(
          width: 400,
          height: 280,
          child: ListView(
            children: [
              for (final v in vendas)
                ListTile(
                  dense: true,
                  title: Text(
                    'Nota ${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
                  ),
                  subtitle: Text(
                    _baseCalculo == 'lucro'
                        ? 'Lucro ${_fmt(v.lucroTotal)}'
                        : 'Total ${_fmt(v.total)}',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    mostrarDetalheVendaRelatorio(
                      context,
                      vendaRepository: widget.vendaRepository,
                      vendaId: v.id,
                    );
                  },
                ),
            ],
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
    final vendedoresOpcoes =
        (widget.vendedorRepository.listarTodos() as List).cast<Vendedor>();
    final lim = _limites;
    final periodoAnt =
        lim != null && _compararPeriodo ? relatorioPeriodoAnterior(lim) : null;
    final comAnt = lim != null && _compararPeriodo
        ? _calcularComissaoTotalPeriodo(periodoAnt!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comissao de vendedores'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'comissao_vendedores',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: _onPeriodo,
            onAtualizar: _limites != null ? _recalcular : null,
            filtrosExtras: [
              if (lim != null)
                RelatorioSwitchComparativo(
                  value: _compararPeriodo,
                  periodoAnterior: periodoAnt,
                  onChanged: (v) => setState(() => _compararPeriodo = v),
                ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'venda',
                    label: Text('Base: valor da venda'),
                    icon: Icon(Icons.shopping_cart_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'lucro',
                    label: Text('Base: lucro'),
                    icon: Icon(Icons.trending_up_outlined),
                  ),
                ],
                emptySelectionAllowed: false,
                selected: {_baseCalculo},
                onSelectionChanged: (set) {
                  setState(() => _baseCalculo = set.first);
                  _recalcular();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Somente vendedores ativos'),
                subtitle: const Text(
                  'Oculta vendas ligadas a cadastros marcados como inativos.',
                ),
                value: _somenteVendedoresAtivos,
                onChanged: (v) {
                  setState(() => _somenteVendedoresAtivos = v);
                  _recalcular();
                },
              ),
              DropdownButtonFormField<int?>(
                key: ValueKey(_filtroVendedorId),
                initialValue: _filtroVendedorId,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por vendedor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  const DropdownMenuItem<int?>(
                    value: 0,
                    child: Text('Sem vendedor'),
                  ),
                  ...vendedoresOpcoes.map(
                    (v) => DropdownMenuItem<int?>(
                      value: v.id,
                      child: Text(_nomeVendedor(v, v.id)),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() => _filtroVendedorId = val);
                  _recalcular();
                },
              ),
            ],
            resumo: lim == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatarIntervaloPeriodo(lim),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Base $_baseCalculo: ${_fmt(_totalBase)} · '
                        'Comissoes: ${_fmt(_totalComissao)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      if (_compararPeriodo && comAnt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Comissao periodo ant.: ${_fmt(comAnt)} · '
                          '${relatorioFormatarVariacaoPct(_totalComissao, comAnt)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: relatorioCorVariacao(
                                  context,
                                  _totalComissao,
                                  comAnt,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _limites == null
                            ? 'Selecione o periodo.'
                            : 'Nenhuma venda no periodo com os filtros atuais.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final r = _linhas[i];
                      final w = r.vendedor;
                      String? refMeta;
                      Widget? barraMeta;
                      if (w != null && w.metaMensalValor > 0 && _limites != null) {
                        final metaProp = relatorioMetaProporcional(
                          w.metaMensalValor,
                          _limites!,
                        );
                        final ating = metaProp > 0.001
                            ? (r.base / metaProp).clamp(0.0, 1.5)
                            : 0.0;
                        refMeta =
                            'Meta do periodo ${_fmt(metaProp)} '
                            '(mensal ${_fmt(w.metaMensalValor)}) · '
                            '${(ating * 100).toStringAsFixed(0)}%';
                        barraMeta = Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(
                            value: ating > 1 ? 1 : ating,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${i + 1}'),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(r.nomeExibicao)),
                            if (r.inativo)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Chip(
                                  label: const Text('Inativo'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.qtd} venda(s) · Base ${_fmt(r.base)} · '
                              '${_pctFmt.format(r.pct)}% · Comissao ${_fmt(r.comissao)}',
                            ),
                            if (barraMeta != null) barraMeta,
                            if (refMeta != null)
                              Text(
                                refMeta,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        isThreeLine: refMeta != null,
                        onTap: () => _detalheComissaoVendedor(
                          r.vendedorId,
                          r.nomeExibicao,
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

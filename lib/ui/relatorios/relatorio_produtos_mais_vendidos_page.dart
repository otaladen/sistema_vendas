import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/venda_repository.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class _AggProd {
  _AggProd({required this.nome, required this.produtoId});

  final String nome;
  final int produtoId;
  int quantidade = 0;
  double valor = 0;
  double lucro = 0;

  double get margemPct => valor.abs() < 0.01 ? 0 : (lucro / valor) * 100;
}

class RelatorioProdutosMaisVendidosPage extends StatefulWidget {
  const RelatorioProdutosMaisVendidosPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final dynamic vendaRepository;
  final dynamic produtoRepository;

  @override
  State<RelatorioProdutosMaisVendidosPage> createState() =>
      _RelatorioProdutosMaisVendidosPageState();
}

class _RelatorioProdutosMaisVendidosPageState
    extends State<RelatorioProdutosMaisVendidosPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  String _ordenarPor = 'quantidade';
  List<_AggProd> _ranking = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  void _agregarVendas(LimitesPeriodo limites, Map<String, _AggProd> map) {
    final vendas = relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    for (final Venda v in vendas) {
      for (final item in relatorioItensDaVenda(widget.vendaRepository, v)) {
        final pid = item.produto.targetId;
        final chave = pid > 0 ? 'id:$pid' : 'nome:${item.nomeProduto}';
        final nome = pid > 0
            ? ((widget.produtoRepository.obterPorId(pid) as Produto?)?.nome ??
                item.nomeProduto)
            : item.nomeProduto;
        map.putIfAbsent(chave, () => _AggProd(nome: nome, produtoId: pid));
        final a = map[chave]!;
        a.quantidade += item.quantidade;
        a.valor += item.subtotal;
        a.lucro += relatorioLucroItemVenda(
          quantidade: item.quantidade,
          quantidadeDevolvida: item.quantidadeDevolvida,
          precoUnitario: item.precoUnitario,
          precoCustoUnitario: item.precoCustoUnitario,
        );
      }
    }
    final deltas = (widget.vendaRepository.listarDeltasProdutosDevolucaoPeriodo(
          relatorioPeriodoFiltro(limites),
        ) as List)
        .cast<DeltaProdutoDevolucao>();
    for (final DeltaProdutoDevolucao d in deltas) {
      map.putIfAbsent(
        d.chaveAgg,
        () => _AggProd(nome: d.nomeExibicao, produtoId: d.produtoId),
      );
      final a = map[d.chaveAgg]!;
      a.quantidade += d.deltaQuantidade;
      a.valor += d.deltaValor;
    }
  }

  void _calcular(LimitesPeriodo limites) {
    final map = <String, _AggProd>{};
    _agregarVendas(limites, map);
    var lista = map.values.where((a) => a.quantidade > 0).toList();
    lista = _ordenar(lista);
    setState(() {
      _limites = limites;
      _ranking = lista;
    });
  }

  List<_AggProd> _ordenar(List<_AggProd> lista) {
    switch (_ordenarPor) {
      case 'valor':
        lista.sort((a, b) => b.valor.compareTo(a.valor));
      case 'lucro':
        lista.sort((a, b) => b.lucro.compareTo(a.lucro));
      default:
        lista.sort((a, b) => b.quantidade.compareTo(a.quantidade));
    }
    return lista;
  }

  Map<String, _AggProd> _mapPeriodo(LimitesPeriodo limites) {
    final map = <String, _AggProd>{};
    _agregarVendas(limites, map);
    return map;
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
        ['#', 'Produto', 'Quantidade', 'Valor', 'Lucro', 'Margem %'],
        ..._ranking.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nome,
                '${e.value.quantidade}',
                _moeda.format(e.value.valor),
                _moeda.format(e.value.lucro),
                e.value.margemPct.toStringAsFixed(1),
              ],
            ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: 'PRODUTOS MAIS VENDIDOS',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['#', 'Produto', 'Qtd', 'Valor', 'Lucro'],
      linhas: _ranking.asMap().entries.map((e) {
        final a = e.value;
        return [
          '${e.key + 1}',
          a.nome,
          '${a.quantidade}',
          _fmt(a.valor),
          _fmt(a.lucro),
        ];
      }).toList(),
    );
  }

  String _chaveAgg(_AggProd a) =>
      a.produtoId > 0 ? 'id:${a.produtoId}' : 'nome:${a.nome}';

  String? _rotuloVariacao(_AggProd a) {
    if (!_compararPeriodo || _limites == null) return null;
    final ant = _mapPeriodo(relatorioPeriodoAnterior(_limites!))[_chaveAgg(a)];
    if (ant == null) return 'novo no periodo ant.';
    final atual = switch (_ordenarPor) {
      'valor' => a.valor,
      'lucro' => a.lucro,
      _ => a.quantidade.toDouble(),
    };
    final anterior = switch (_ordenarPor) {
      'valor' => ant.valor,
      'lucro' => ant.lucro,
      _ => ant.quantidade.toDouble(),
    };
    return relatorioFormatarVariacaoPct(atual, anterior);
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final t = _totaisAtual;
    final periodoAnt =
        lim != null && _compararPeriodo ? relatorioPeriodoAnterior(lim) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produtos mais vendidos'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'produtos_mais_vendidos',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: _calcular,
            onAtualizar: lim != null ? () => _calcular(lim) : null,
            filtrosExtras: [
              if (lim != null)
                RelatorioSwitchComparativo(
                  value: _compararPeriodo,
                  periodoAnterior: periodoAnt,
                  onChanged: (v) => setState(() => _compararPeriodo = v),
                ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'quantidade', label: Text('Qtd')),
                  ButtonSegment(value: 'valor', label: Text('Valor')),
                  ButtonSegment(value: 'lucro', label: Text('Lucro')),
                ],
                emptySelectionAllowed: false,
                selected: {_ordenarPor},
                onSelectionChanged: (s) {
                  setState(() {
                    _ordenarPor = s.first;
                    if (lim != null) _ranking = _ordenar(List.from(_ranking));
                  });
                },
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
            child: _ranking.isEmpty
                ? const Center(child: Text('Nenhum item vendido no periodo.'))
                : ListView.builder(
                    itemCount: _ranking.length,
                    itemBuilder: (context, i) {
                      final a = _ranking[i];
                      final varPct = _rotuloVariacao(a);
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(a.nome),
                        subtitle: Text(
                          '${a.quantidade} un. · ${_fmt(a.valor)} · '
                          'Lucro ${_fmt(a.lucro)} · '
                          '${a.margemPct.toStringAsFixed(1)}%'
                          '${varPct != null ? ' · $varPct vs ant.' : ''}',
                        ),
                        trailing: a.produtoId > 0
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: a.produtoId > 0
                            ? () => abrirProdutoRelatorio(
                                  context,
                                  produtoRepository: widget.produtoRepository,
                                  produtoId: a.produtoId,
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

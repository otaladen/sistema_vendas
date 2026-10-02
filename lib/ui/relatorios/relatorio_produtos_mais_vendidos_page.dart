import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/produtos_mais_vendidos_repository.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

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
  final NumberFormat _qtd = NumberFormat('#,##0.###', 'pt_BR');
  LimitesPeriodo? _limites;
  bool _compararPeriodo = false;
  String _ordenarPor = 'quantidade';
  List<ProdutoMaisVendidoLinha> _ranking = [];

  late final ProdutosMaisVendidosRepository _repo = ProdutosMaisVendidosRepository(
    vendaRepository: widget.vendaRepository,
    produtoRepository: widget.produtoRepository,
  );

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  String _fmtQtd(double q) => _qtd.format(q);

  void _calcular(LimitesPeriodo limites) {
    setState(() {
      _limites = limites;
      _ranking = _repo.listarRanking(limites, ordenarPor: _ordenarPor);
    });
  }

  Map<String, ProdutoMaisVendidoLinha> _mapPeriodo(LimitesPeriodo limites) =>
      _repo.agregarPeriodo(limites);

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
          'Produto',
          'Quantidade',
          'Valor',
          'Lucro',
          'Margem %',
          'Revisar cadastro',
        ],
        ..._ranking.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nome,
                _fmtQtd(e.value.quantidade),
                _moeda.format(e.value.faturamentoTotal),
                _moeda.format(e.value.lucro),
                e.value.margemIrreal
                    ? '—'
                    : e.value.margemPercentual.toStringAsFixed(1),
                e.value.margemIrreal ? 'sim' : '',
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
          _fmtQtd(a.quantidade),
          _fmt(a.faturamentoTotal),
          _fmt(a.lucro),
        ];
      }).toList(),
    );
  }

  String _chaveAgg(ProdutoMaisVendidoLinha a) =>
      a.produtoId > 0 ? 'id:${a.produtoId}' : 'nome:${a.nome}';

  String? _rotuloVariacao(ProdutoMaisVendidoLinha a) {
    if (!_compararPeriodo || _limites == null) return null;
    final ant = _mapPeriodo(relatorioPeriodoAnterior(_limites!))[_chaveAgg(a)];
    if (ant == null) return 'novo no periodo ant.';
    final atual = switch (_ordenarPor) {
      'valor' => a.faturamentoTotal,
      'lucro' => a.lucro,
      _ => a.quantidade,
    };
    final anterior = switch (_ordenarPor) {
      'valor' => ant.faturamentoTotal,
      'lucro' => ant.lucro,
      _ => ant.quantidade,
    };
    return relatorioFormatarVariacaoPct(atual, anterior);
  }

  String _rotuloMargem(ProdutoMaisVendidoLinha a) {
    if (a.margemIrreal) {
      return 'Margem irreal — revisar cadastro/escala';
    }
    return '${a.margemPercentual.toStringAsFixed(1)}%';
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
                    if (lim != null) {
                      _ranking =
                          _repo.listarRanking(lim, ordenarPor: _ordenarPor);
                    }
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
                          '${_fmtQtd(a.quantidade)} un. · ${_fmt(a.faturamentoTotal)} · '
                          'Lucro ${_fmt(a.lucro)} · '
                          '${_rotuloMargem(a)}'
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

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/venda_repository.dart';
import '../../domain/relatorio_margem_markup.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioMargemMarkupPage extends StatefulWidget {
  const RelatorioMargemMarkupPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final dynamic vendaRepository;
  final dynamic produtoRepository;

  @override
  State<RelatorioMargemMarkupPage> createState() =>
      _RelatorioMargemMarkupPageState();
}

class _RelatorioMargemMarkupPageState extends State<RelatorioMargemMarkupPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  LimitesPeriodo? _limites;
  List<RelatorioMargemLinha> _produtos = [];
  List<RelatorioMargemLinha> _categorias = [];

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _calcular(LimitesPeriodo limites) {
    final porProduto = <String, RelatorioMargemLinha>{};
    final porCategoria = <String, RelatorioMargemLinha>{};
    final vendas =
        relatorioVendasFinalizadasPeriodo(widget.vendaRepository, limites);
    for (final Venda v in vendas) {
      for (final item in relatorioItensDaVenda(widget.vendaRepository, v)) {
        final pid = item.produto.targetId;
        final Produto? prod = pid > 0
            ? widget.produtoRepository.obterPorId(pid) as Produto?
            : null;
        final nome = pid > 0
            ? (prod?.nome ?? item.nomeProduto)
            : item.nomeProduto;
        final chave = pid > 0 ? 'id:$pid' : 'nome:${item.nomeProduto}';
        final qtdLiq = item.quantidade - item.quantidadeDevolvida;
        final cmv = qtdLiq <= 0 ? 0.0 : qtdLiq * item.precoCustoUnitario;
        RelatorioMargemMarkup.acumular(
          porProduto,
          chave: chave,
          nome: nome,
          produtoId: pid,
          receita: item.subtotal,
          cmv: cmv,
        );
        final cat = (prod?.categoria ?? '').trim();
        RelatorioMargemMarkup.acumular(
          porCategoria,
          chave: cat.isEmpty ? 'sem_categoria' : cat.toLowerCase(),
          nome: cat.isEmpty ? 'Sem categoria' : cat,
          receita: item.subtotal,
          cmv: cmv,
        );
      }
    }
    final deltas = (widget.vendaRepository.listarDeltasProdutosDevolucaoPeriodo(
          relatorioPeriodoFiltro(limites),
        ) as List)
        .cast<DeltaProdutoDevolucao>();
    for (final d in deltas) {
      RelatorioMargemMarkup.acumular(
        porProduto,
        chave: d.chaveAgg,
        nome: d.nomeExibicao,
        produtoId: d.produtoId,
        receita: d.deltaValor,
        cmv: 0,
      );
      final Produto? prod = d.produtoId > 0
          ? widget.produtoRepository.obterPorId(d.produtoId) as Produto?
          : null;
      final cat = (prod?.categoria ?? '').trim();
      RelatorioMargemMarkup.acumular(
        porCategoria,
        chave: cat.isEmpty ? 'sem_categoria' : cat.toLowerCase(),
        nome: cat.isEmpty ? 'Sem categoria' : cat,
        receita: d.deltaValor,
        cmv: 0,
      );
    }
    setState(() {
      _limites = limites;
      _produtos = RelatorioMargemMarkup.ordenarPorLucro(porProduto.values);
      _categorias = RelatorioMargemMarkup.ordenarPorLucro(porCategoria.values);
    });
  }

  List<RelatorioMargemLinha> get _lista =>
      _tabs.index == 0 ? _produtos : _categorias;

  List<List<String>> _linhasCsv() => [
        [
          '#',
          _tabs.index == 0 ? 'Produto' : 'Categoria',
          'Receita',
          'CMV',
          'Lucro',
          'Margem %',
          'Markup %',
        ],
        ..._lista.asMap().entries.map(
              (e) => [
                '${e.key + 1}',
                e.value.nome,
                _moeda.format(e.value.receita),
                _moeda.format(e.value.cmv),
                _moeda.format(e.value.lucro),
                e.value.margemPct.toStringAsFixed(1),
                e.value.markupPct.toStringAsFixed(1),
              ],
            ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: _tabs.index == 0
          ? 'MARGEM E MARKUP — PRODUTOS'
          : 'MARGEM E MARKUP — CATEGORIAS',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['#', 'Nome', 'Receita', 'Lucro', 'Margem', 'Markup'],
      linhas: _lista.asMap().entries.map((e) {
        final a = e.value;
        return [
          '${e.key + 1}',
          a.nome,
          _fmt(a.receita),
          _fmt(a.lucro),
          '${a.margemPct.toStringAsFixed(1)}%',
          '${a.markupPct.toStringAsFixed(1)}%',
        ];
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Margem bruta e markup'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'margem_markup',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Produtos'),
            Tab(text: 'Categorias'),
          ],
        ),
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: _calcular,
            onAtualizar: lim != null ? () => _calcular(lim) : null,
            resumo: lim == null
                ? null
                : Text(
                    '${formatarIntervaloPeriodo(lim)} · ${_lista.length} linha(s). '
                    'Receita liquida de devolucao; markup = receita/CMV - 1.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _lista.isEmpty
                ? const Center(child: Text('Nenhuma venda no periodo.'))
                : ListView.builder(
                    itemCount: _lista.length,
                    itemBuilder: (context, i) {
                      final a = _lista[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(a.nome),
                        subtitle: Text(
                          'Receita ${_fmt(a.receita)} · CMV ${_fmt(a.cmv)} · '
                          'Lucro ${_fmt(a.lucro)}',
                        ),
                        trailing: Text(
                          '${a.margemPct.toStringAsFixed(1)}%\n'
                          '${a.markupPct.toStringAsFixed(1)}% mk',
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        onTap: _tabs.index == 0 && a.produtoId > 0
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

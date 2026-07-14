import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/movimento_estoque_repository.dart';
import '../../data/objectbox.dart';
import '../../data/produto_repository.dart';
import '../../domain/estoque/movimento_estoque_helper.dart';
import '../../domain/relatorios/movimentacao_estoque_relatorio.dart';
import '../../model/produto.dart';
import '../widgets/produto_busca_input.dart';
import 'relatorio_export_util.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioMovimentacaoEstoquePage extends StatefulWidget {
  const RelatorioMovimentacaoEstoquePage({
    super.key,
    required this.produtoRepository,
    required this.objectBox,
  });

  final ProdutoRepository produtoRepository;
  final ObjectBox objectBox;

  @override
  State<RelatorioMovimentacaoEstoquePage> createState() =>
      _RelatorioMovimentacaoEstoquePageState();
}

class _RelatorioMovimentacaoEstoquePageState
    extends State<RelatorioMovimentacaoEstoquePage> {
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');
  final DateFormat _fmtDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

  LimitesPeriodo? _limites;
  AgrupamentoMovimentacaoEstoque _agrupamento =
      AgrupamentoMovimentacaoEstoque.produto;
  FiltroNaturezaMovimentacaoEstoque _natureza =
      FiltroNaturezaMovimentacaoEstoque.todas;
  bool _somenteAtivos = true;
  bool _modoDetalhe = false;
  Produto? _produtoFiltro;

  List<ResumoMovimentacaoEstoqueLinha> _resumo = [];
  List<DetalheMovimentacaoEstoqueLinha> _detalhes = [];

  MovimentoEstoqueRepository get _movRepo =>
      MovimentoEstoqueRepository(widget.objectBox);

  Map<int, Produto> get _produtosPorId {
    final map = <int, Produto>{};
    for (final p in widget.produtoRepository.listarTodos()) {
      map[p.id] = p;
    }
    return map;
  }

  Produto? _resolverProdutoPorTexto(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return null;
    final porBarras = widget.produtoRepository.resolverLeitorCodigoBarras(
      t,
      somenteAtivos: false,
    );
    if (porBarras != null) return porBarras;
    final hits = widget.produtoRepository.pesquisarPadraoPdv(
      t,
      limite: 20,
      somenteAtivos: false,
    );
    if (hits.isEmpty) return null;
    if (hits.length == 1) return hits.first;
    final lower = t.toLowerCase();
    for (final p in hits) {
      if (p.codigoInterno.toLowerCase() == lower) return p;
    }
    return hits.first;
  }

  Iterable<Produto> _sugestoesProduto(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return const Iterable<Produto>.empty();
    final porBarras = widget.produtoRepository.resolverLeitorCodigoBarras(
      t,
      somenteAtivos: false,
    );
    if (porBarras != null) return [porBarras];
    return widget.produtoRepository.pesquisarPadraoPdv(
      t,
      limite: 40,
      somenteAtivos: false,
    );
  }

  void _aplicarProduto(Produto? p) {
    setState(() => _produtoFiltro = p);
    if (_limites != null) _carregar(_limites!);
  }

  void _confirmarBuscaProduto(String texto) {
    final p = _resolverProdutoPorTexto(texto);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto nao encontrado.')),
      );
      return;
    }
    _aplicarProduto(p);
  }

  void _carregar(LimitesPeriodo limites) {
    final movimentos = _movRepo.listarPorPeriodo(
      inicio: limites.$1,
      fim: limites.$2,
      produtoId: _produtoFiltro?.id,
    );
    final produtos = _produtosPorId;
    final resumo = agregarMovimentacaoEstoque(
      movimentos: movimentos,
      produtosPorId: produtos,
      agrupamento: _agrupamento,
      natureza: _natureza,
      produtoIdFiltro: _produtoFiltro?.id,
      somenteAtivos: _somenteAtivos,
    );
    final detalhes = detalharMovimentacaoEstoque(
      movimentos: movimentos,
      produtosPorId: produtos,
      natureza: _natureza,
      produtoIdFiltro: _produtoFiltro?.id,
      somenteAtivos: _somenteAtivos,
    );
    setState(() {
      _limites = limites;
      _resumo = resumo;
      _detalhes = detalhes;
    });
  }

  int get _totalEntradas => _resumo.fold(0, (s, l) => s + l.entradas);
  int get _totalSaidas => _resumo.fold(0, (s, l) => s + l.saidas);

  List<List<String>> _linhasCsvResumo() => [
        [
          'Grupo',
          'Codigo',
          'Entradas',
          'Saidas',
          'Cancelamentos',
          'Saldo inicial',
          'Saldo final',
          'Movimentos',
        ],
        ..._resumo.map(
          (l) => [
            l.rotulo,
            l.codigo,
            '${l.entradas}',
            '${l.saidas}',
            '${l.cancelamentos}',
            '${l.saldoInicial}',
            '${l.saldoFinal}',
            '${l.movimentos}',
          ],
        ),
      ];

  List<List<String>> _linhasCsvDetalhe() => [
        [
          'Data',
          'Produto',
          'Tipo',
          'Delta fisico',
          'Delta reserva',
          'Saldo',
          'Documento',
          'Motivo',
          'Usuario',
        ],
        ..._detalhes.map(
          (l) => [
            _fmtDataHora.format(l.registradoEm),
            l.nomeProduto,
            MovimentoEstoqueHelper.rotuloTipo(l.tipoMovimento),
            '${l.deltaFisico}',
            '${l.deltaReserva}',
            '${l.saldoFisicoDepois}',
            l.documentoReferencia,
            l.motivo,
            l.usuarioLogin,
          ],
        ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    final subtitulo = formatarIntervaloPeriodo(_limites!);
    if (_modoDetalhe) {
      return relatorioMontarPaginasTabela(
        titulo: 'MOVIMENTACAO ESTOQUE — DETALHE',
        subtitulo: subtitulo,
        cabecalho: ['Data', 'Produto', 'Tipo', 'Delta', 'Saldo', 'Doc.'],
        linhas: _detalhes
            .take(500)
            .map(
              (l) => [
                _fmtDataHora.format(l.registradoEm),
                l.nomeProduto,
                MovimentoEstoqueHelper.rotuloTipo(l.tipoMovimento),
                '${l.deltaFisico}',
                '${l.saldoFisicoDepois}',
                l.documentoReferencia,
              ],
            )
            .toList(),
      );
    }
    return relatorioMontarPaginasTabela(
      titulo: 'MOVIMENTACAO ESTOQUE — RESUMO',
      subtitulo: subtitulo,
      cabecalho: [
        'Grupo',
        'Entr.',
        'Said.',
        'Canc.',
        'Saldo ini.',
        'Saldo fim.',
      ],
      linhas: _resumo
          .take(500)
          .map(
            (l) => [
              l.rotulo,
              '${l.entradas}',
              '${l.saidas}',
              '${l.cancelamentos}',
              '${l.saldoInicial}',
              '${l.saldoFinal}',
            ],
          )
          .toList(),
    );
  }

  String _rotuloAgrupamento(AgrupamentoMovimentacaoEstoque a) {
    switch (a) {
      case AgrupamentoMovimentacaoEstoque.produto:
        return 'Produto';
      case AgrupamentoMovimentacaoEstoque.categoria:
        return 'Categoria';
      case AgrupamentoMovimentacaoEstoque.subcategoria:
        return 'Subcategoria';
      case AgrupamentoMovimentacaoEstoque.marca:
        return 'Marca';
    }
  }

  String _rotuloNatureza(FiltroNaturezaMovimentacaoEstoque n) {
    switch (n) {
      case FiltroNaturezaMovimentacaoEstoque.todas:
        return 'Todas';
      case FiltroNaturezaMovimentacaoEstoque.entradas:
        return 'Entradas';
      case FiltroNaturezaMovimentacaoEstoque.saidas:
        return 'Saidas';
      case FiltroNaturezaMovimentacaoEstoque.devolucoes:
        return 'Devolucoes';
      case FiltroNaturezaMovimentacaoEstoque.cancelamentos:
        return 'Cancelamentos';
      case FiltroNaturezaMovimentacaoEstoque.ajustes:
        return 'Ajustes';
      case FiltroNaturezaMovimentacaoEstoque.reservas:
        return 'Reservas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final vazio = _modoDetalhe ? _detalhes.isEmpty : _resumo.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimentacao de estoque'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: _modoDetalhe
                ? 'movimentacao_estoque_detalhe'
                : 'movimentacao_estoque_resumo',
            paginasPdf: _paginasPdf,
            linhasCsv: _modoDetalhe ? _linhasCsvDetalhe : _linhasCsvResumo,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: _carregar,
            onAtualizar: lim != null ? () => _carregar(lim) : null,
            filtrosExtras: [
              Autocomplete<Produto>(
                displayStringForOption: (p) => '${p.codigoInterno} · ${p.nome}',
                optionsBuilder: (te) => _sugestoesProduto(te.text),
                onSelected: _aplicarProduto,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: produtoBuscaInputDecoration(
                      labelText: 'Produto (opcional)',
                      hintText: 'Filtrar um produto',
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _confirmarBuscaProduto(controller.text),
                    onEditingComplete: onFieldSubmitted,
                  );
                },
              ),
              if (_produtoFiltro != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _aplicarProduto(null),
                    icon: const Icon(Icons.clear, size: 18),
                    label: Text(
                      'Limpar filtro: ${_produtoFiltro!.codigoInterno}',
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<AgrupamentoMovimentacaoEstoque>(
                      key: ValueKey(_agrupamento),
                      initialValue: _agrupamento,
                      decoration: const InputDecoration(
                        labelText: 'Agrupar por',
                        isDense: true,
                      ),
                      items: AgrupamentoMovimentacaoEstoque.values
                          .map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(_rotuloAgrupamento(a)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _agrupamento = v);
                        if (lim != null) _carregar(lim);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<FiltroNaturezaMovimentacaoEstoque>(
                      key: ValueKey(_natureza),
                      initialValue: _natureza,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        isDense: true,
                      ),
                      items: FiltroNaturezaMovimentacaoEstoque.values
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text(_rotuloNatureza(n)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _natureza = v);
                        if (lim != null) _carregar(lim);
                      },
                    ),
                  ),
                  FilterChip(
                    label: const Text('Mostrar inativos'),
                    selected: !_somenteAtivos,
                    onSelected: (v) {
                      setState(() => _somenteAtivos = !v);
                      if (lim != null) _carregar(lim);
                    },
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Resumo')),
                      ButtonSegment(value: true, label: Text('Detalhe')),
                    ],
                    emptySelectionAllowed: false,
                    selected: {_modoDetalhe},
                    onSelectionChanged: (s) =>
                        setState(() => _modoDetalhe = s.first),
                  ),
                ],
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
                      const SizedBox(height: 6),
                      Text(
                        'Entradas: ${_nfInt.format(_totalEntradas)} · '
                        'Saidas: ${_nfInt.format(_totalSaidas)} · '
                        '${_modoDetalhe ? _detalhes.length : _resumo.length} '
                        'linha(s)',
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: vazio
                ? const Center(
                    child: Text('Nenhuma movimentacao no periodo com estes filtros.'),
                  )
                : _modoDetalhe
                    ? ListView.separated(
                        itemCount: _detalhes.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final l = _detalhes[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${l.codigoProduto.isNotEmpty ? "${l.codigoProduto} — " : ""}'
                              '${l.nomeProduto}',
                            ),
                            subtitle: Text(
                              '${_fmtDataHora.format(l.registradoEm)} · '
                              '${MovimentoEstoqueHelper.rotuloTipo(l.tipoMovimento)} · '
                              'Fisico ${MovimentoEstoqueHelper.formatarDelta(l.deltaFisico)} · '
                              'Saldo ${l.saldoFisicoDepois}'
                              '${l.documentoReferencia.isNotEmpty ? " · ${l.documentoReferencia}" : ""}'
                              '${l.motivo.isNotEmpty ? " · ${l.motivo}" : ""}',
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        itemCount: _resumo.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final l = _resumo[i];
                          return ListTile(
                            title: Text(l.rotulo),
                            subtitle: Text(
                              'Entr. ${_nfInt.format(l.entradas)} · '
                              'Said. ${_nfInt.format(l.saidas)} · '
                              'Canc. ${_nfInt.format(l.cancelamentos)} · '
                              'Saldo ${_nfInt.format(l.saldoInicial)} → '
                              '${_nfInt.format(l.saldoFinal)} · '
                              '${l.movimentos} mov.',
                            ),
                            onTap: l.produtoId > 0
                                ? () {
                                    final p = _produtosPorId[l.produtoId];
                                    if (p == null) return;
                                    setState(() {
                                      _produtoFiltro = p;
                                      _modoDetalhe = true;
                                      _agrupamento =
                                          AgrupamentoMovimentacaoEstoque.produto;
                                    });
                                    if (lim != null) _carregar(lim);
                                  }
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

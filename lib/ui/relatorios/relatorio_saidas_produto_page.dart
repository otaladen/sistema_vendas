import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/produto_repository.dart';
import '../widgets/produto_busca_input.dart';
import '../../data/venda_repository.dart';
import '../../model/produto.dart';
import 'relatorio_drill_down.dart';
import 'relatorio_pdf_acoes.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioSaidasProdutoPage extends StatefulWidget {
  const RelatorioSaidasProdutoPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioSaidasProdutoPage> createState() =>
      _RelatorioSaidasProdutoPageState();
}

class _RelatorioSaidasProdutoPageState extends State<RelatorioSaidasProdutoPage> {
  LimitesPeriodo? _limites;
  Produto? _produto;
  List<SaidaProdutoRelatorioLinha> _linhas = [];
  final _buscaProdutoController = TextEditingController();

  final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');

  @override
  void dispose() {
    _buscaProdutoController.dispose();
    super.dispose();
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

  void _aplicarProduto(Produto? p, {String? textoBusca}) {
    setState(() {
      _produto = p;
      if (p != null) {
        _buscaProdutoController.text = '${p.codigoInterno} · ${p.nome}';
      } else if (textoBusca != null) {
        _buscaProdutoController.text = textoBusca;
      }
    });
    _carregar();
  }

  void _buscarProdutoPorCampo() {
    final p = _resolverProdutoPorTexto(_buscaProdutoController.text);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Produto nao encontrado. Use codigo exato ou escolha na lista.',
          ),
        ),
      );
      return;
    }
    _aplicarProduto(p);
  }

  void _carregar() {
    final p = _produto;
    final lim = _limites;
    if (p == null || lim == null) {
      setState(() => _linhas = []);
      return;
    }
    final lista = widget.vendaRepository.listarSaidasProdutoPeriodo(
      produtoId: p.id,
      inicio: lim.$1,
      fim: lim.$2,
    );
    setState(() => _linhas = lista);
  }

  String _fmtMoeda(double v) => 'R\$ ${_nfMoeda.format(v)}';

  String _linhaPdf(SaidaProdutoRelatorioLinha l) {
    String t(String s, int w) =>
        s.length > w ? s.substring(0, w) : s.padRight(w);
    String n(String s, int w) => s.padLeft(w);
    final d = DateFormat('dd/MM/yyyy').format(l.dataVenda);
    return '${t(d, 12)} ${n(_nfInt.format(l.quantidade), 12)} '
        '${n(_nfMoeda.format(l.valorUnitario), 12)} '
        '${n(_nfMoeda.format(l.total), 12)} '
        '${n('${l.nota}', 8)} '
        '${n(_nfMoeda.format(l.lucro), 12)} '
        '${n(_nfMoeda.format(l.acrescimo), 10)} '
        '${t(l.clienteNome, 26)}';
  }

  List<String> _montarPaginasPdf(String tituloProduto, String periodoRotulo) {
    const maxLinhas = 52;
    final cab = StringBuffer()
      ..writeln('SAIDAS DO PRODUTO (vendas finalizadas)')
      ..writeln(tituloProduto)
      ..writeln('Periodo: $periodoRotulo')
      ..writeln()
      ..writeln(
        '${'DATA'.padRight(12)} ${'QTD'.padLeft(12)} ${'VLR_UNIT'.padLeft(12)} '
        '${'TOTAL'.padLeft(12)} ${'NOTA'.padLeft(8)} ${'LUCRO'.padLeft(12)} '
        '${'ACRESC'.padLeft(10)} ${'CLIENTE'.padRight(26)}',
      )
      ..writeln('-' * 96);

    for (final l in _linhas) {
      cab.writeln(_linhaPdf(l));
    }
    cab.writeln('-' * 96);
    final tQ = _linhas.fold<int>(0, (s, e) => s + e.quantidade);
    final tV = _linhas.fold<double>(0, (s, e) => s + e.total);
    final tL = _linhas.fold<double>(0, (s, e) => s + e.lucro);
    String pn(String s, int w) => s.padLeft(w);
    cab.writeln(
      '${'TOTAIS'.padRight(12)} ${pn(_nfInt.format(tQ), 12)} ${''.padLeft(12)} '
      '${pn(_nfMoeda.format(tV), 12)} ${''.padLeft(8)} ${pn(_nfMoeda.format(tL), 12)}',
    );

    final texto = cab.toString();
    final linhas = texto.split('\n');
    final paginas = <String>[];
    for (var i = 0; i < linhas.length; i += maxLinhas) {
      final fim = math.min(i + maxLinhas, linhas.length);
      paginas.add(linhas.sublist(i, fim).join('\n'));
    }
    return paginas.isEmpty ? <String>['(vazio)'] : paginas;
  }

  List<String> _paginasAtuais() {
    final p = _produto;
    final lim = _limites;
    if (p == null || lim == null) return [];
    final iniFmt = DateFormat('dd/MM/yyyy').format(lim.$1);
    final fimFmt = DateFormat('dd/MM/yyyy').format(lim.$2);
    return _montarPaginasPdf(p.nome, '$iniFmt a $fimFmt');
  }

  String _nomeArquivoPdf() {
    final p = _produto!;
    final lim = _limites!;
    final ini = DateFormat('yyyyMMdd').format(lim.$1);
    final fim = DateFormat('yyyyMMdd').format(lim.$2);
    final seguro = p.codigoInterno.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return 'saidas_produto_${seguro}_$ini-$fim';
  }

  List<List<String>> _linhasCsv() {
    final p = _produto;
    return [
      [
        'Data',
        'Qtd',
        'Valor unit',
        'Total',
        'Nota',
        'Lucro',
        'Acrescimo',
        'Cliente',
      ],
      ..._linhas.map(
        (l) => [
          DateFormat('dd/MM/yyyy').format(l.dataVenda),
          '${l.quantidade}',
          _nfMoeda.format(l.valorUnitario),
          _nfMoeda.format(l.total),
          '${l.nota}',
          _nfMoeda.format(l.lucro),
          _nfMoeda.format(l.acrescimo),
          l.clienteNome,
        ],
      ),
      if (p != null) ['Produto', p.codigoInterno, p.nome, '', '', '', '', ''],
    ];
  }

  Future<void> _imprimirPdf() async {
    if (_produto == null || _limites == null || _linhas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione produto e periodo com linhas para imprimir.'),
        ),
      );
      return;
    }
    await RelatorioPdfAcoes.imprimirPaginas(
      context,
      paginas: _paginasAtuais(),
    );
  }

  Future<void> _salvarPdf() async {
    if (_produto == null || _limites == null || _linhas.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para exportar neste periodo.')),
      );
      return;
    }
    await RelatorioPdfAcoes.salvarPaginas(
      context,
      paginas: _paginasAtuais(),
      nomeArquivoSemExtensao: _nomeArquivoPdf(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tQ = _linhas.fold<int>(0, (s, e) => s + e.quantidade);
    final tV = _linhas.fold<double>(0, (s, e) => s + e.total);
    final tL = _linhas.fold<double>(0, (s, e) => s + e.lucro);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saidas por produto'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: _produto != null
                ? 'saidas_${_produto!.codigoInterno}'
                : 'saidas_produto',
            paginasPdf: _paginasAtuais,
            linhasCsv: _linhasCsv,
          ),
          ...RelatorioPdfAcoes.appBarBotoes(
            onImprimir: _imprimirPdf,
            onSalvar: _salvarPdf,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: (lim) {
              setState(() => _limites = lim);
              _carregar();
            },
            onAtualizar: _carregar,
            filtrosExtras: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaProdutoController,
                      decoration: produtoBuscaInputDecoration(
                        labelText: 'Codigo ou nome do produto',
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscarProdutoPorCampo(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Buscar produto',
                    onPressed: _buscarProdutoPorCampo,
                    icon: const Icon(Icons.search),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Autocomplete<Produto>(
                displayStringForOption: (p) => '${p.codigoInterno} · ${p.nome}',
                optionsBuilder: (TextEditingValue te) => _sugestoesProduto(te.text),
                onSelected: (p) => _aplicarProduto(p),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Ou escolha na lista (2+ letras)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onEditingComplete: onFieldSubmitted,
                  );
                },
              ),
              if (_produto != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => abrirProdutoRelatorio(
                      context,
                      produtoRepository: widget.produtoRepository,
                      produtoId: _produto!.id,
                    ),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Ver ficha do produto'),
                  ),
                ),
            ],
            resumo: _produto == null && _limites == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_produto != null)
                        Text(
                          'Produto: ${_produto!.nome} (${_produto!.codigoInterno})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      if (_limites != null) ...[
                        if (_produto != null) const SizedBox(height: 4),
                        Text(formatarIntervaloPeriodo(_limites!)),
                      ],
                      if (_produto != null && _limites != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Qtd total: ${_nfInt.format(tQ)} · '
                          'Valor: ${_fmtMoeda(tV)} · Lucro: ${_fmtMoeda(tL)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Text(
                      _produto == null
                          ? 'Informe o codigo ou selecione um produto.'
                          : 'Nenhuma saida no periodo (vendas finalizadas, quantidade liquida > 0).',
                    ),
                  )
                : Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _linhas.length,
                      itemBuilder: (context, i) {
                        final l = _linhas[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              '${DateFormat('dd/MM/yyyy').format(l.dataVenda)} · '
                              'Qtd ${_nfInt.format(l.quantidade)} · '
                              'Total ${_fmtMoeda(l.total)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Unit ${_fmtMoeda(l.valorUnitario)} · '
                              'Lucro ${_fmtMoeda(l.lucro)} · '
                              'Nota ${l.nota} · ${l.clienteNome}',
                            ),
                            trailing: l.vendaId > 0
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: l.vendaId > 0
                                ? () => mostrarDetalheVendaRelatorio(
                                      context,
                                      vendaRepository: widget.vendaRepository,
                                      vendaId: l.vendaId,
                                    )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

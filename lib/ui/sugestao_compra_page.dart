import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../data/api/lan_api_client.dart';
import '../data/api/produto_api_repository.dart';
import '../data/produto_repository.dart';
import '../data/sugestao_compra_repository.dart';
import '../domain/produto_embalagem.dart';
import '../services/compras_preditivas_service.dart';
import '../services/pdf_relatorio_texto.dart';
import 'theme/app_semantic_colors.dart';

/// Relatorio de reposicao: giro recente, minimo, ponto de pedido e ultima entrada por NF-e.
class SugestaoCompraPage extends StatefulWidget {
  const SugestaoCompraPage({
    super.key,
    required this.produtoRepository,
    this.lanApiClient,
  });

  final dynamic produtoRepository;
  final LanApiClient? lanApiClient;

  @override
  State<SugestaoCompraPage> createState() => _SugestaoCompraPageState();
}

class _SugestaoCompraPageState extends State<SugestaoCompraPage> {
  int _diasPeriodo = 60;
  int _diasCoberturaAlvo = 30;
  bool _apenasPrioritarios = true;
  String? _fornecedorFiltro;
  List<String> _fornecedores = const [];
  bool _carregando = false;
  String? _erro;
  List<LinhaSugestaoCompra> _linhas = const [];
  static final _dataFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dec1 = NumberFormat('#,##0.0', 'pt_BR');

  bool get _modoRemoto =>
      widget.produtoRepository is ProdutoApiRepository ||
      widget.lanApiClient != null;

  LanApiClient? get _client {
    if (widget.lanApiClient != null) return widget.lanApiClient;
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) return repo.client;
    return null;
  }

  SugestaoCompraRepository? get _repoLocal {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoRepository) return null;
    try {
      return SugestaoCompraRepository(repo.objectBox);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_carregarLinhas());
  }

  Future<void> _carregarLinhas() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      if (_modoRemoto) {
        final client = _client;
        if (client == null) {
          throw StateError('Sem conexao com o PC servidor.');
        }
        final raw = await client.listarSugestaoCompra(
          diasPeriodo: _diasPeriodo,
          diasCobertura: _diasCoberturaAlvo,
          apenasPrioritarios: _apenasPrioritarios,
          fornecedor: _fornecedorFiltro,
        );
        final linhas = <LinhaSugestaoCompra>[];
        for (final m in raw.items) {
          final l = LinhaSugestaoCompra.fromApiMap(m);
          if (l != null) linhas.add(l);
        }
        if (!mounted) return;
        setState(() {
          _linhas = linhas;
          if (raw.fornecedores.isNotEmpty) {
            _fornecedores = raw.fornecedores;
          }
          if (_fornecedorFiltro != null &&
              !_fornecedores.contains(_fornecedorFiltro)) {
            _fornecedorFiltro = null;
          }
          _carregando = false;
        });
        return;
      }
      final repo = _repoLocal;
      if (repo == null) {
        throw StateError('Sugestao de compra indisponivel neste terminal.');
      }
      final linhas = repo.montarLinhas(
        diasPeriodoConsumo: _diasPeriodo,
        diasCoberturaAlvo: _diasCoberturaAlvo,
        apenasComSugestaoOuRisco: _apenasPrioritarios,
        fornecedorFiltro: _fornecedorFiltro,
      );
      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _fornecedores = repo.indiceFornecedoresNfe().nomesOrdenados;
        if (_fornecedorFiltro != null &&
            !_fornecedores.contains(_fornecedorFiltro)) {
          _fornecedorFiltro = null;
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = '$e';
        _linhas = const [];
      });
    }
  }

  String _csvSeguro(String valor) {
    final texto = valor.replaceAll('"', '""');
    return '"$texto"';
  }

  Future<void> _exportarCsv() async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar o CSV de sugestao de compra',
    );
    if (pasta == null || pasta.trim().isEmpty) return;

    final linhas = _linhas;
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final sufixo = _fornecedorFiltro == null
        ? ''
        : '_${_slugArquivo(_fornecedorFiltro!)}';
    final arquivo = File(p.join(pasta, 'sugestao_compra${sufixo}_$ts.csv'));

    final out = <String>[
      'Fornecedor;SKU;Nome;Unidade;Atual;Livre;Minimo;PP;Critico PP;Media dia;Lead time;Seguranca;Vendido periodo;Cobertura dias;Ultima NF-e;Sugerido comprar;Sugerido PP',
    ];
    for (final l in linhas) {
      final pr = l.produto;
      final dias = l.diasCoberturaComEstoqueAtual;
      final diasStr = dias == null ? '' : _dec1.format(dias);
      final ult = l.ultimaEntradaNfe == null
          ? ''
          : _dataFmt.format(l.ultimaEntradaNfe!.toLocal());
      out.add([
        _csvSeguro(
          l.fornecedorUltimaNfe.isEmpty
              ? (pr.fornecedor)
              : l.fornecedorUltimaNfe,
        ),
        _csvSeguro(pr.codigoInterno),
        _csvSeguro(pr.nome),
        _csvSeguro(pr.unidade),
        ProdutoEmbalagem.formatarEstoque(pr, pr.estoqueAtual, comUnidade: true),
        ProdutoEmbalagem.formatarEstoque(
          pr,
          pr.estoqueLivreParaVenda,
          comUnidade: true,
        ),
        '${pr.quantidadeMinima}',
        _dec1.format(l.pontoPedido).replaceAll('.', ','),
        l.estoqueCritico ? 'SIM' : 'NAO',
        ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(
          pr,
          l.mediaUnidadesPorDia,
        ),
        '${pr.leadTimeDias}',
        '${pr.estoqueSeguranca}',
        ProdutoEmbalagem.formatarEstoque(pr, l.consumoNoPeriodoUnidades),
        diasStr.replaceAll('.', ','),
        ult,
        '${l.quantidadeSugerida}',
        '${l.quantidadeSugeridaPorPp}',
      ].join(';'));
    }

    try {
      await arquivo.writeAsString('\uFEFF${out.join('\n')}', encoding: utf8);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV salvo em: ${arquivo.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar: $e')),
      );
    }
  }

  Future<void> _recalcularMediasTodosProdutos() async {
    if (_modoRemoto) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recalculo de medias deve ser feito no PC servidor.',
          ),
        ),
      );
      return;
    }
    final repo = widget.produtoRepository;
    if (repo is! ProdutoRepository) return;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Text('Recalculando medias de venda (60 dias)...'),
              ),
            ],
          ),
        ),
      ),
    );

    final svc = ComprasPreditivasService(repo.objectBox);
    final atualizados = await svc.recalcularTodosProdutosAtivosAsync();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await _carregarLinhas();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          'Medias recalculadas para $atualizados produto(s) ativo(s).',
        ),
      ),
    );
  }

  String _slugArquivo(String nome) {
    final t = nome
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (t.isEmpty) return 'fornecedor';
    return t.length > 40 ? t.substring(0, 40) : t;
  }

  String _textoPedidoRepresentante() {
    final buf = StringBuffer();
    buf.writeln('Pedido de reposicao');
    if (_fornecedorFiltro != null && _fornecedorFiltro!.trim().isNotEmpty) {
      buf.writeln('Fornecedor: ${_fornecedorFiltro!.trim()}');
    }
    buf.writeln(
      'Gerado em ${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(DateTime.now())}',
    );
    buf.writeln('');
    var n = 1;
    for (final l in _linhas) {
      final pr = l.produto;
      final forn = l.fornecedorUltimaNfe.trim().isNotEmpty
          ? l.fornecedorUltimaNfe.trim()
          : pr.fornecedor.trim();
      buf.write('$n. ${pr.nome}');
      if (pr.codigoInterno.trim().isNotEmpty) {
        buf.write(' (SKU ${pr.codigoInterno.trim()})');
      }
      buf.writeln(
        ' — ${l.quantidadeSugerida} ${ProdutoEmbalagem.normalizarUnidade(pr.unidade)}',
      );
      buf.writeln(
        '   Estoque ${ProdutoEmbalagem.formatarEstoque(pr, pr.estoqueAtual)} · '
        'min ${pr.quantidadeMinima} · PP ${_dec1.format(l.pontoPedido)}',
      );
      if (_fornecedorFiltro == null && forn.isNotEmpty) {
        buf.writeln('   Fornecedor: $forn');
      }
      n++;
    }
    return buf.toString().trim();
  }

  Future<void> _copiarTextoRepresentante() async {
    final texto = _textoPedidoRepresentante();
    if (texto.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lista copiada para colar no WhatsApp.')),
    );
  }

  Future<void> _exportarPdf() async {
    final titulo = _fornecedorFiltro == null || _fornecedorFiltro!.trim().isEmpty
        ? 'Sugestao de compra'
        : 'Pedido — ${_fornecedorFiltro!.trim()}';
    final bytes = await gerarPdfRelatorioTextoPaginas([
      '$titulo\n\n${_textoPedidoRepresentante()}',
    ]);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  void _onFiltroChanged(VoidCallback apply) {
    apply();
    unawaited(_carregarLinhas());
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    final qtdCriticosPp = linhas.where((l) => l.estoqueCritico).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestao de compra'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : () => unawaited(_carregarLinhas()),
            icon: const Icon(Icons.sync_outlined),
          ),
          IconButton(
            tooltip: 'Recalcular media diaria de todos os produtos',
            onPressed: _modoRemoto || _carregando
                ? null
                : () => _recalcularMediasTodosProdutos(),
            icon: const Icon(Icons.refresh_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportar lista',
            enabled: linhas.isNotEmpty && !_carregando,
            onSelected: (v) {
              if (v == 'csv') unawaited(_exportarCsv());
              if (v == 'pdf') unawaited(_exportarPdf());
              if (v == 'copiar') unawaited(_copiarTextoRepresentante());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
              PopupMenuItem(value: 'pdf', child: Text('Imprimir / PDF')),
              PopupMenuItem(
                value: 'copiar',
                child: Text('Copiar texto para o representante'),
              ),
            ],
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usa vendas finalizadas, estoque minimo, ponto de pedido (PP) e meta de cobertura. '
                  'PP = (media diaria x lead time) + estoque seguranca.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (_modoRemoto) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Dados calculados no PC servidor via API.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Periodo de venda:'),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 30, label: Text('30 d')),
                        ButtonSegment(value: 60, label: Text('60 d')),
                        ButtonSegment(value: 90, label: Text('90 d')),
                      ],
                      selected: {_diasPeriodo},
                      onSelectionChanged: _carregando
                          ? null
                          : (s) {
                              if (s.isEmpty) return;
                              _onFiltroChanged(
                                () => setState(() => _diasPeriodo = s.first),
                              );
                            },
                    ),
                    const Text('Meta cobertura:'),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 21, label: Text('21 d')),
                        ButtonSegment(value: 30, label: Text('30 d')),
                        ButtonSegment(value: 45, label: Text('45 d')),
                      ],
                      selected: {_diasCoberturaAlvo},
                      onSelectionChanged: _carregando
                          ? null
                          : (s) {
                              if (s.isEmpty) return;
                              _onFiltroChanged(
                                () => setState(
                                  () => _diasCoberturaAlvo = s.first,
                                ),
                              );
                            },
                    ),
                    FilterChip(
                      label: const Text('So prioritarios'),
                      selected: _apenasPrioritarios,
                      onSelected: _carregando
                          ? null
                          : (s) => _onFiltroChanged(
                                () => setState(() => _apenasPrioritarios = s),
                              ),
                    ),
                    if (_fornecedores.isNotEmpty)
                      DropdownMenu<String?>(
                        key: ValueKey(
                          'forn_${_fornecedores.length}_${_fornecedorFiltro ?? ''}',
                        ),
                        width: 280,
                        label: const Text('Fornecedor'),
                        initialSelection: _fornecedorFiltro,
                        dropdownMenuEntries: [
                          const DropdownMenuEntry<String?>(
                            value: null,
                            label: 'Todos',
                          ),
                          for (final f in _fornecedores)
                            DropdownMenuEntry<String?>(value: f, label: f),
                        ],
                        onSelected: _carregando
                            ? null
                            : (v) => _onFiltroChanged(
                                  () => setState(() => _fornecedorFiltro = v),
                                ),
                      ),
                  ],
                ),
                if (_fornecedorFiltro != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'So SKUs com NF-e/compra desse fornecedor abaixo do ponto de pedido ou do estoque minimo.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _carregando
                      ? 'Carregando...'
                      : '${linhas.length} produto(s) · $qtdCriticosPp em PP critico',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : linhas.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _erro != null
                                ? 'Nao foi possivel carregar a sugestao.'
                                : _fornecedorFiltro != null
                                    ? 'Nenhum produto desse fornecedor esta abaixo do ponto de pedido ou do estoque minimo.'
                                    : _apenasPrioritarios
                                    ? 'Nenhum produto em alerta com os filtros atuais.\n'
                                        'Desative "So prioritarios" para ver todos os cadastros ativos.'
                                    : 'Nenhum produto ativo no cadastro.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: linhas.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final l = linhas[i];
                          final pr = l.produto;
                          final livre = pr.estoqueLivreExibicao;
                          final abaixoMin = livre <= pr.quantidadeMinima;
                          final dias = l.diasCoberturaComEstoqueAtual;
                          final giroBaixo =
                              dias != null && dias < _diasCoberturaAlvo;
                          final semantic = Theme.of(context)
                              .extension<AppSemanticColors>();

                          return Card(
                            color: l.estoqueCritico
                                ? (semantic?.errorBg ??
                                        Theme.of(context)
                                            .colorScheme
                                            .errorContainer)
                                    .withValues(alpha: 0.25)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          pr.nome,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (l.estoqueCritico)
                                        Chip(
                                          label: Text(
                                            l.alertaPorEstoqueSeguranca
                                                ? 'Seguranca'
                                                : 'PP critico',
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                        ),
                                      if (!l.estoqueCritico && abaixoMin)
                                        Chip(
                                          label: const Text('Minimo'),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                        ),
                                      if (!l.estoqueCritico &&
                                          !abaixoMin &&
                                          giroBaixo)
                                        Chip(
                                          label: const Text('Giro'),
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .tertiaryContainer,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'SKU ${pr.codigoInterno} · ${pr.unidade} · '
                                    'Atual ${ProdutoEmbalagem.formatarEstoque(pr, pr.estoqueAtual, comUnidade: true)} · '
                                    'Livre ${ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(pr, livre)} ${pr.unidade} · '
                                    'Min ${pr.quantidadeMinima}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l.alertaPorEstoqueSeguranca
                                        ? 'Limiar seguranca: ${_dec1.format(l.pontoPedido)} un '
                                            '(produto novo ou sem giro no periodo)'
                                        : 'PP ${_dec1.format(l.pontoPedido)} un '
                                            '(media ${_dec1.format(l.mediaUnidadesPorDia)}/dia x '
                                            '${pr.leadTimeDias}d + seg ${pr.estoqueSeguranca})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    'Vendido ($_diasPeriodo d): ${l.consumoNoPeriodoUnidades} un',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    dias == null
                                        ? 'Cobertura: — (sem venda no periodo)'
                                        : 'Cobertura estimada: ${_dec1.format(dias)} dias de estoque livre',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    l.ultimaEntradaNfe == null
                                        ? 'Ultima NF-e: —'
                                        : 'Ultima NF-e: ${_dataFmt.format(l.ultimaEntradaNfe!.toLocal())}'
                                            '${l.fornecedorUltimaNfe.trim().isEmpty ? '' : ' · ${l.fornecedorUltimaNfe.trim()}'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sugerido comprar: ${l.quantidadeSugerida} ${pr.unidade}'
                                    '${l.quantidadeSugeridaPorPp > 0 ? ' (ate PP: ${l.quantidadeSugeridaPorPp})' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/produto_busca_util.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../domain/promocao_info_vigente.dart';
import '../domain/promocao_preco_result.dart';
import '../model/produto.dart';
import 'pdv_consulta_preview_panel.dart';
import 'pdv_pesquisa_comando.dart';
import 'produto_detalhe_venda_page.dart';
import 'widgets/pdv_consulta_linha_produto.dart';

/// Resultado ao escolher (ou atalho rapido) na consulta de produtos do PDV.
class PdvConsultaProdutoResult {
  const PdvConsultaProdutoResult({
    required this.produto,
    required this.precoListaAtivo,
    this.quantidadeDireta,
    this.adicaoDireta = false,
    this.abrirDialogoAdicionar = true,
  });

  final Produto produto;
  final String precoListaAtivo;
  final int? quantidadeDireta;
  final bool adicaoDireta;
  final bool abrirDialogoAdicionar;
}

/// Tela cheia de consulta (lista + teclado). Aberta a partir do carrinho.
class PdvConsultaProdutosPage extends StatefulWidget {
  const PdvConsultaProdutosPage({
    super.key,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.termoInicial,
    required this.precoListaAtivoInicial,
    required this.clienteId,
    required this.produtosRecentesIds,
    required this.formatarMoeda,
    required this.rotuloPreco,
    required this.precoUnitarioDe,
    this.resolverPromocao,
    this.campanhasVigentesDe,
    this.quantidadeNoOrcamentoDe,
  });

  final ProdutoRepository produtoRepository;
  final VendaRepository vendaRepository;
  final String termoInicial;
  final String precoListaAtivoInicial;
  final int? clienteId;
  final List<int> produtosRecentesIds;
  final String Function(double) formatarMoeda;
  final String Function(String) rotuloPreco;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final PromocaoPrecoResult Function(Produto produto, String precoTipo)?
      resolverPromocao;
  final List<PromocaoInfoVigente> Function(Produto produto)?
      campanhasVigentesDe;
  final int Function(int produtoId)? quantidadeNoOrcamentoDe;

  @override
  State<PdvConsultaProdutosPage> createState() =>
      _PdvConsultaProdutosPageState();
}

class _PdvConsultaProdutosPageState extends State<PdvConsultaProdutosPage> {
  static const double _alturaLinha = PdvConsultaLinhaProduto.alturaLinha;
  static const double _larguraPainelPreview = 280;
  static const double _breakpointPainelLateral = 720;

  late final TextEditingController _pesquisaController;
  late final FocusNode _pesquisaFocus;
  late final FocusNode _listaFocus;
  late final ScrollController _scrollController;
  Timer? _debounce;

  late String _precoListaAtivo;
  List<Produto> _produtos = [];
  int? _indiceSelecionado;
  String _subtituloLista = '';
  String _termoBuscaAtual = '';

  /// Montada uma vez (recentes + ranking); evita travar ao apagar o texto.
  List<Produto>? _cacheSugestoes;

  @override
  void initState() {
    super.initState();
    _precoListaAtivo = widget.precoListaAtivoInicial;
    _pesquisaController = TextEditingController(text: widget.termoInicial);
    _pesquisaFocus = FocusNode(debugLabel: 'pdvConsultaPesquisa');
    _listaFocus = FocusNode(debugLabel: 'pdvConsultaLista');
    _scrollController = ScrollController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_produtos.isEmpty) {
      _atualizarLista(
        confirmarSeUmResultado: widget.termoInicial.trim().isNotEmpty,
        focarListaSeTiverItens: widget.termoInicial.trim().isNotEmpty,
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pesquisaController.dispose();
    _pesquisaFocus.dispose();
    _listaFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _agendarBuscaDigitacao() {
    _debounce?.cancel();
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    if (consultaEanProvavelCompleto(termo)) {
      _debounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _atualizarLista(
          confirmarSeUmResultado: true,
          manterFocoNaPesquisa: true,
        );
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _atualizarLista(manterFocoNaPesquisa: true);
    });
  }

  /// [confirmarSeUmResultado]: so ao Enter/busca explicita (nao enquanto digita).
  void _atualizarLista({
    bool confirmarSeUmResultado = false,
    bool manterFocoNaPesquisa = false,
    bool focarListaSeTiverItens = false,
  }) {
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    List<Produto> lista;
    String subtitulo;

    if (termo.isEmpty) {
      lista = _listaSugestoes();
      subtitulo = lista.isEmpty
          ? 'Nenhum produto ativo cadastrado'
          : 'Recentes e mais vendidos (30 dias)';
    } else {
      final porBarras = widget.produtoRepository.resolverLeitorCodigoBarras(
        termo,
      );
      if (porBarras != null) {
        lista = [porBarras];
        subtitulo = 'Codigo de barras: $termo';
      } else {
        lista = widget.produtoRepository.pesquisarPadraoPdv(
          termo,
          clienteId: widget.clienteId,
          limite: 50,
        );
        subtitulo = '${lista.length} resultado(s) para "$termo"';
      }
    }

    if (confirmarSeUmResultado && lista.length == 1) {
      _confirmarProduto(lista.first, comando: comando);
      return;
    }

    if (!mounted) return;
    setState(() {
      _produtos = lista;
      _subtituloLista = subtitulo;
      _termoBuscaAtual = termo;
      _indiceSelecionado = lista.isEmpty ? null : 0;
    });

    if (lista.isNotEmpty) {
      _reposicionarListaAposBusca();
    }

    if (manterFocoNaPesquisa) return;

    if (focarListaSeTiverItens && lista.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _listaFocus.requestFocus();
      });
    }
  }

  List<Produto> _listaSugestoes() {
    if (_cacheSugestoes != null) return _cacheSugestoes!;

    final vistos = <int>{};
    final out = <Produto>[];

    void addId(int id) {
      if (id <= 0 || vistos.contains(id)) return;
      final p = widget.produtoRepository.obterPorId(id);
      if (p == null || !p.ativo || produtoEhCadastroInternoSistema(p)) return;
      vistos.add(id);
      out.add(p);
    }

    for (final id in widget.produtosRecentesIds) {
      addId(id);
      if (out.length >= 50) break;
    }

    if (out.length < 50) {
      final ranking = widget.vendaRepository.listarProdutoIdsMaisVendidos(
        dias: 30,
        limite: 50,
      );
      for (final id in ranking) {
        addId(id);
        if (out.length >= 50) break;
      }
    }

    if (out.length < 20) {
      for (final p in widget.produtoRepository.listarPaginado(
        limit: 50,
        somenteAtivos: true,
      )) {
        addId(p.id);
        if (out.length >= 50) break;
      }
    }

    _cacheSugestoes = out;
    return out;
  }

  void _scrollParaIndice() {
    final i = _indiceSelecionado;
    if (i == null) return;
    _scrollParaOffsetIndice(i);
  }

  void _scrollParaOffsetIndice(int indice) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final target = (indice * _alturaLinha).clamp(0.0, max);
    if ((_scrollController.offset - target).abs() > 0.5) {
      _scrollController.jumpTo(target);
    }
  }

  /// Apos nova busca, garante que o 1º resultado fique visivel (lista nao fica
  /// com o scroll da pesquisa anterior).
  void _reposicionarListaAposBusca() {
    var tentativas = 0;
    void tentar() {
      if (!mounted) return;
      tentativas++;
      if (_scrollController.hasClients) {
        _scrollParaOffsetIndice(_indiceSelecionado ?? 0);
        return;
      }
      if (tentativas < 4) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tentar());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tentar());
  }

  bool _estoqueCritico(Produto p) => p.estoqueReal < p.quantidadeMinima;

  Produto? get _produtoSelecionado {
    final i = _indiceSelecionado;
    if (i == null || i < 0 || i >= _produtos.length) return null;
    return _produtos[i];
  }

  void _selecionarIndice(int index) {
    if (index < 0 || index >= _produtos.length) return;
    setState(() => _indiceSelecionado = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndice();
      _listaFocus.requestFocus();
    });
  }

  Future<void> _abrirDetalhesProduto() async {
    final p = _produtoSelecionado;
    if (p == null) return;
    await mostrarModalDetalheProdutoVenda(
      context,
      produto: p,
      campanhasVigentes: widget.campanhasVigentesDe?.call(p) ?? const [],
    );
    if (!mounted) return;
    _listaFocus.requestFocus();
  }

  void _focarCampoBusca() {
    _pesquisaFocus.requestFocus();
    final texto = _pesquisaController.text;
    _pesquisaController.selection = TextSelection.collapsed(offset: texto.length);
  }

  void _focarListaPrimeiroItem() {
    if (_produtos.isEmpty) return;
    setState(() => _indiceSelecionado = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollParaIndice();
      _listaFocus.requestFocus();
    });
  }

  bool _shiftPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool _ehTeclaMais(KeyDownEvent event) =>
      event.logicalKey == LogicalKeyboardKey.numpadAdd ||
      (_shiftPressionado() && event.logicalKey == LogicalKeyboardKey.equal);

  void _confirmarProduto(
    Produto produto, {
    PdvPesquisaComando? comando,
  }) {
    final cmd = comando ?? PdvPesquisaComando.parse(_pesquisaController.text);
    Navigator.of(context).pop(
      PdvConsultaProdutoResult(
        produto: produto,
        precoListaAtivo: _precoListaAtivo,
        quantidadeDireta: cmd.quantidadeDireta,
        adicaoDireta: cmd.adicaoDireta,
        abrirDialogoAdicionar:
            !cmd.adicaoDireta && cmd.quantidadeDireta == null,
      ),
    );
  }

  KeyEventResult _onKeyLista(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_produtos.isEmpty) return KeyEventResult.ignored;

    final n = _produtos.length;
    var i = _indiceSelecionado ?? 0;
    i = i.clamp(0, n - 1);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _indiceSelecionado = (i + 1).clamp(0, n - 1));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaIndice());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (i == 0) {
        _focarCampoBusca();
        return KeyEventResult.handled;
      }
      setState(() => _indiceSelecionado = i - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollParaIndice());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f8) {
      _focarCampoBusca();
      return KeyEventResult.handled;
    }
    if (_ehTeclaMais(event)) {
      Navigator.of(context).pop(
        PdvConsultaProdutoResult(
          produto: _produtos[i],
          precoListaAtivo: _precoListaAtivo,
          adicaoDireta: true,
          abrirDialogoAdicionar: false,
        ),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirmarProduto(_produtos[i]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.f9) {
      _abrirDetalhesProduto();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildPainelPreview(Produto produto, {required bool compacto}) {
    final campanhas = widget.campanhasVigentesDe?.call(produto) ?? const [];
    return PdvConsultaPreviewPanel(
      produto: produto,
      precoListaAtivo: _precoListaAtivo,
      precoUnitarioDe: widget.precoUnitarioDe,
      rotuloPreco: widget.rotuloPreco,
      formatarMoeda: widget.formatarMoeda,
      campanhaPromo: campanhas.isNotEmpty ? campanhas.first : null,
      promocaoAtiva: widget.resolverPromocao?.call(produto, _precoListaAtivo),
      estoqueCritico: _estoqueCritico(produto),
      compacto: compacto,
      quantidadeNoOrcamento:
          widget.quantidadeNoOrcamentoDe?.call(produto.id) ?? 0,
      onDetalhes: _abrirDetalhesProduto,
    );
  }

  Widget _buildListaProdutos() {
    return Focus(
      focusNode: _listaFocus,
      onKeyEvent: _onKeyLista,
      child: ListView.builder(
        key: ValueKey<String>(
          'pdv-consulta-$_termoBuscaAtual-${_produtos.length}',
        ),
        controller: _scrollController,
        itemExtent: _alturaLinha,
        itemCount: _produtos.length,
        itemBuilder: (context, index) {
          final item = _produtos[index];
          final selecionado = _indiceSelecionado == index;
          final scheme = Theme.of(context).colorScheme;
          final res = widget.resolverPromocao?.call(item, _precoListaAtivo);
          final preco = res?.precoFinal ??
              widget.precoUnitarioDe(item, _precoListaAtivo);
          final emPromo = res?.emPromocao ?? false;
          final precoDe = emPromo
              ? widget.formatarMoeda(res!.precoBasePreco1)
              : null;
          final critico = _estoqueCritico(item);
          return Material(
            color: selecionado
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : (index.isOdd ? scheme.surfaceContainerLow : scheme.surface),
            child: InkWell(
              onTap: () => _selecionarIndice(index),
              onDoubleTap: () => _confirmarProduto(item),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: PdvConsultaLinhaProduto(
                  produto: item,
                  termoBusca: _termoBuscaAtual,
                  precoFormatado: widget.formatarMoeda(preco),
                  emPromocao: emPromo,
                  precoDeFormatado: precoDe,
                  estoqueCritico: critico,
                  tooltipAdicionar:
                      'Adicionar 1 (${widget.rotuloPreco(_precoListaAtivo)})',
                  onAdicionar: () {
                    Navigator.of(context).pop(
                      PdvConsultaProdutoResult(
                        produto: item,
                        precoListaAtivo: _precoListaAtivo,
                        adicaoDireta: true,
                        abrirDialogoAdicionar: false,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAreaListaComPreview() {
    final selecionado = _produtoSelecionado;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painelLateral = constraints.maxWidth >= _breakpointPainelLateral;
        if (selecionado == null) {
          return _buildListaProdutos();
        }
        if (painelLateral) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildListaProdutos()),
              SizedBox(
                width: _larguraPainelPreview,
                child: _buildPainelPreview(selecionado, compacto: false),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 320,
              child: _buildPainelPreview(selecionado, compacto: true),
            ),
            Expanded(child: _buildListaProdutos()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): _PdvConsultaPrecoIntent('preco1'),
        SingleActivator(LogicalKeyboardKey.f2): _PdvConsultaPrecoIntent('preco2'),
        SingleActivator(LogicalKeyboardKey.f3): _PdvConsultaPrecoIntent('preco3'),
        SingleActivator(LogicalKeyboardKey.f8): _PdvConsultaFocoBuscaIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _PdvConsultaFecharIntent(),
      },
      child: Actions(
        actions: {
          _PdvConsultaFocoBuscaIntent: CallbackAction<_PdvConsultaFocoBuscaIntent>(
            onInvoke: (_) {
              _focarCampoBusca();
              return null;
            },
          ),
          _PdvConsultaPrecoIntent: CallbackAction<_PdvConsultaPrecoIntent>(
            onInvoke: (intent) {
              setState(() => _precoListaAtivo = intent.precoTipo);
              return null;
            },
          ),
          _PdvConsultaFecharIntent: CallbackAction<_PdvConsultaFecharIntent>(
            onInvoke: (_) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Voltar ao carrinho (Esc)',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Consulta de produtos'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.f8):
                        _focarCampoBusca,
                    const SingleActivator(LogicalKeyboardKey.arrowDown):
                        _focarListaPrimeiroItem,
                  },
                  child: TextField(
                      controller: _pesquisaController,
                      focusNode: _pesquisaFocus,
                      autofocus: widget.termoInicial.isEmpty,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Filtrar na consulta',
                        helperText:
                            'Palavras: tubo sod 25 · Trechos: tub%sod%25',
                        hintText: 'Nome, codigo ou codigo de barras',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _atualizarLista(
                            confirmarSeUmResultado: true,
                            focarListaSeTiverItens: true,
                          ),
                        ),
                      ),
                      onChanged: (_) => _agendarBuscaDigitacao(),
                      onSubmitted: (_) => _atualizarLista(
                        confirmarSeUmResultado: true,
                        focarListaSeTiverItens: true,
                      ),
                    ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Lista ativa: ${widget.rotuloPreco(_precoListaAtivo)} · '
                  'painel mostra os 3 precos · F1–F3 troca lista · '
                  'F8 foco filtro · setas lista/filtro · Enter confirma · '
                  'Espaco/F9 detalhes · '
                  'duplo clique confirma · Esc volta · Numpad+ adiciona 1',
                  style: Theme.of(context).textTheme.bodySmall,
                  softWrap: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  _subtituloLista,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Expanded(
                child: _produtos.isEmpty
                    ? const Center(child: Text('Nenhum produto encontrado.'))
                    : _buildAreaListaComPreview(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdvConsultaPrecoIntent extends Intent {
  const _PdvConsultaPrecoIntent(this.precoTipo);
  final String precoTipo;
}

class _PdvConsultaFocoBuscaIntent extends Intent {
  const _PdvConsultaFocoBuscaIntent();
}

class _PdvConsultaFecharIntent extends Intent {
  const _PdvConsultaFecharIntent();
}

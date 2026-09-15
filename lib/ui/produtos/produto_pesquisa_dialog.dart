import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/api/produto_api_repository.dart';
import '../../data/produto_busca_util.dart';
import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../../services/produto_imagem_lan_service.dart';
import '../../services/produto_imagem_service.dart';
import '../layout/app_layout.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/pdv_consulta_semaforo_estoque.dart';
import '../widgets/pdv_estoque_resumo_panel.dart';
import '../widgets/produto_busca_input.dart';
import '../widgets/produto_foto_view.dart';

const int _kLoteInicialExibicao = 35;
const int _kLoteScrollExibicao = 35;
const int _kLoteRepoVazio = 40;
const int _kLimiteBuscaTexto = 350;
const int _kDebounceBuscaMs = 260;
const int _kDebounceCliqueLinhaMs = 260;
const double _kAlturaLinha = 36.0;
const double _kAlturaLinhaCelular = 52.0;
const double _kMiniaturaPx = 26.0;
const double _kAlturaCabecalhoGrade = 28.0;
const double _kMargemDialogo = 16.0;
const double _kLarguraPainelDetalhe = 320;
const String _kTodasCategorias = '';

final NumberFormat _moedaListaProduto = NumberFormat('#,##0.00', 'pt_BR');

/// Ordenacao client-side da lista (apos busca / paginacao).
enum ProdutoPesquisaOrdenacao {
  nomeAz,
  estoqueMenor,
  estoqueMaior,
  precoMaior,
  precoMenor,
  codigo,
}

extension ProdutoPesquisaOrdenacaoRotulo on ProdutoPesquisaOrdenacao {
  String get rotulo => switch (this) {
        ProdutoPesquisaOrdenacao.nomeAz => 'Nome A-Z',
        ProdutoPesquisaOrdenacao.estoqueMenor => 'Menor estoque',
        ProdutoPesquisaOrdenacao.estoqueMaior => 'Maior estoque',
        ProdutoPesquisaOrdenacao.precoMaior => 'Maior preco',
        ProdutoPesquisaOrdenacao.precoMenor => 'Menor preco',
        ProdutoPesquisaOrdenacao.codigo => 'Codigo',
      };
}

/// Larguras fixas das colunas da lista (desktop / tela cheia).
class _ProdutoPesquisaColunas {
  static const double larguraMarcacao = 36;
  static const double larguraCodigo = 100;
  static const double larguraUnidade = 56;
  static const double larguraPrecoColuna = 92;
  static const double larguraEstoque = 118;
  static const double larguraFoto = _kMiniaturaPx + 8;
  static const EdgeInsets paddingCelula =
      EdgeInsets.symmetric(vertical: 4, horizontal: 8);
  static const int flexDescricao = 5;
  static const int flexCategoria = 2;
}

/// Estado da pesquisa no cadastro de produtos (persiste entre aberturas do dialogo).
class ProdutoPesquisaCadastroSessao {
  String textoPesquisa = '';
  bool somenteInativos = false;
  List<Produto> carregados = const [];
  int exibidos = 0;
  int indiceSelecionado = -1;
  bool temMaisNoRepo = true;
  bool buscaComTexto = false;
  double scrollOffset = 0;
  int? produtoIdEmDestaque;
  String categoriaFiltro = _kTodasCategorias;
  ProdutoPesquisaOrdenacao ordenacao = ProdutoPesquisaOrdenacao.nomeAz;
  bool painelDetalheAberto = false;

  bool get temEstadoSalvo =>
      textoPesquisa.trim().isNotEmpty ||
      carregados.isNotEmpty ||
      somenteInativos ||
      categoriaFiltro.isNotEmpty;

  void limpar() {
    textoPesquisa = '';
    somenteInativos = false;
    carregados = const [];
    exibidos = 0;
    indiceSelecionado = -1;
    temMaisNoRepo = true;
    buscaComTexto = false;
    scrollOffset = 0;
    produtoIdEmDestaque = null;
    categoriaFiltro = _kTodasCategorias;
    ordenacao = ProdutoPesquisaOrdenacao.nomeAz;
    painelDetalheAberto = false;
  }

  void atualizarProdutoSalvo(Produto produto, dynamic produtoRepository) {
    if (produto.id <= 0) return;
    final fresco =
        produtoRepository.obterPorId(produto.id) as Produto? ?? produto;
    produtoIdEmDestaque = fresco.id;
    final idx = carregados.indexWhere((p) => p.id == fresco.id);
    if (idx >= 0) {
      final copia = List<Produto>.from(carregados);
      copia[idx] = fresco;
      carregados = copia;
      indiceSelecionado = idx;
    }
  }

  void removerProduto(int produtoId) {
    if (produtoId <= 0) return;
    final idx = carregados.indexWhere((p) => p.id == produtoId);
    if (idx < 0) return;
    final copia = List<Produto>.from(carregados)..removeAt(idx);
    carregados = copia;
    exibidos = math.min(exibidos, copia.length);
    if (indiceSelecionado >= copia.length) {
      indiceSelecionado = copia.isEmpty ? -1 : copia.length - 1;
    }
    if (produtoIdEmDestaque == produtoId) {
      produtoIdEmDestaque = null;
    }
  }
}

/// Dialogo de pesquisa de produto no cadastro (debounce + scroll progressivo).
Future<Produto?> showProdutoPesquisaDialog({
  required BuildContext context,
  required dynamic produtoRepository,
  ProdutoPesquisaCadastroSessao? sessaoCadastro,
}) {
  return showDialog<Produto>(
    context: context,
    builder: (context) => _ProdutoPesquisaDialog(
      produtoRepository: produtoRepository,
      sessaoCadastro: sessaoCadastro,
    ),
  );
}

class _ProdutoPesquisaDialog extends StatefulWidget {
  const _ProdutoPesquisaDialog({
    required this.produtoRepository,
    this.sessaoCadastro,
  });

  final dynamic produtoRepository;
  final ProdutoPesquisaCadastroSessao? sessaoCadastro;

  @override
  State<_ProdutoPesquisaDialog> createState() => _ProdutoPesquisaDialogState();
}

class _ProdutoPesquisaDialogState extends State<_ProdutoPesquisaDialog> {
  final _pesquisaController = TextEditingController();
  final _scrollController = ScrollController();
  final _pesquisaFocusNode = FocusNode();
  final _listaAtalhosFocusNode = FocusNode();
  Timer? _debounce;
  Timer? _debounceCliqueLinha;

  var _somenteInativos = false;
  var _carregados = <Produto>[];
  var _exibidos = 0;
  final ValueNotifier<int> _exibidosNotifier = ValueNotifier(0);
  final ValueNotifier<int> _indiceSelecionado = ValueNotifier(-1);
  var _temMaisNoRepo = true;
  var _carregando = false;
  var _buscaComTexto = false;
  var _fechando = false;
  final _idsMarcados = <int>{};
  var _excluindo = false;
  var _aplicandoFoto = false;
  var _categoriaFiltro = _kTodasCategorias;
  var _ordenacao = ProdutoPesquisaOrdenacao.nomeAz;
  var _painelDetalheAberto = false;

  bool get _usarPainelDetalhe =>
      widget.sessaoCadastro != null && !context.isCompactLayout;

  List<Produto> get _listaFiltradaOrdenada {
    Iterable<Produto> base = _carregados;
    if (_categoriaFiltro.isNotEmpty) {
      base = base.where(
        (p) => p.categoria.trim().toLowerCase() == _categoriaFiltro.toLowerCase(),
      );
    }
    final lista = base.toList();
    lista.sort(_compararOrdenacao);
    return lista;
  }

  int _compararOrdenacao(Produto a, Produto b) {
    switch (_ordenacao) {
      case ProdutoPesquisaOrdenacao.estoqueMenor:
        final c = a.estoqueReal.compareTo(b.estoqueReal);
        return c != 0 ? c : a.nome.compareTo(b.nome);
      case ProdutoPesquisaOrdenacao.estoqueMaior:
        final c = b.estoqueReal.compareTo(a.estoqueReal);
        return c != 0 ? c : a.nome.compareTo(b.nome);
      case ProdutoPesquisaOrdenacao.precoMaior:
        final c = b.preco2.compareTo(a.preco2);
        return c != 0 ? c : a.nome.compareTo(b.nome);
      case ProdutoPesquisaOrdenacao.precoMenor:
        final c = a.preco2.compareTo(b.preco2);
        return c != 0 ? c : a.nome.compareTo(b.nome);
      case ProdutoPesquisaOrdenacao.codigo:
        final c = a.codigoInterno.trim().compareTo(b.codigoInterno.trim());
        return c != 0 ? c : a.nome.compareTo(b.nome);
      case ProdutoPesquisaOrdenacao.nomeAz:
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    }
  }

  Produto? get _produtoSelecionado {
    final idx = _indiceSelecionado.value;
    final lista = _listaFiltradaOrdenada;
    if (idx < 0 || idx >= lista.length) return null;
    return lista[idx];
  }

  List<String> _categoriasParaFiltro() {
    final set = <String>{};
    for (final p in _carregados) {
      final c = p.categoria.trim();
      if (c.isNotEmpty) set.add(c);
    }
    try {
      final todos = widget.produtoRepository.listarTodos();
      if (todos is List) {
        for (final item in todos) {
          if (item is Produto) {
            final c = item.categoria.trim();
            if (c.isNotEmpty) set.add(c);
          }
        }
      }
    } catch (_) {}
    final lista = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return lista;
  }

  void _ajustarSelecaoAposFiltroOuOrdem({int? produtoIdPreservar}) {
    final lista = _listaFiltradaOrdenada;
    if (lista.isEmpty) {
      _indiceSelecionado.value = -1;
      _atualizarExibidos(0);
      return;
    }
    var novoIndice = 0;
    final idAlvo = produtoIdPreservar ?? _produtoSelecionado?.id;
    if (idAlvo != null) {
      final porId = lista.indexWhere((p) => p.id == idAlvo);
      if (porId >= 0) novoIndice = porId;
    } else if (_indiceSelecionado.value >= 0) {
      novoIndice = math.min(_indiceSelecionado.value, lista.length - 1);
    }
    _indiceSelecionado.value = novoIndice;
    _atualizarExibidos(
      math.min(math.max(_exibidos, _kLoteInicialExibicao), lista.length),
    );
  }

  void _onLinhaTap(int indice, Produto produto) {
    _debounceCliqueLinha?.cancel();
    _debounceCliqueLinha = Timer(
      const Duration(milliseconds: _kDebounceCliqueLinhaMs),
      () {
        if (!mounted) return;
        _executarCliqueSimplesLinha(indice, produto);
      },
    );
  }

  void _onLinhaDuploClique(int indice, Produto produto) {
    _debounceCliqueLinha?.cancel();
    _debounceCliqueLinha = null;
    _indiceSelecionado.value = indice;
    _confirmarSelecionado();
  }

  void _executarCliqueSimplesLinha(int indice, Produto produto) {
    if (_usarPainelDetalhe) {
      if (_indiceSelecionado.value != indice) {
        _definirIndiceSelecionado(indice);
      }
      setState(() => _painelDetalheAberto = true);
      _ativarFocoAtalhosLista();
    } else {
      _fechar(produto);
    }
  }

  void _fecharPainelDetalhe() {
    if (!_painelDetalheAberto) return;
    setState(() => _painelDetalheAberto = false);
  }

  void _ativarFocoAtalhosLista() {
    if (_pesquisaFocusNode.hasFocus) {
      _pesquisaFocusNode.unfocus();
    }
    if (!_listaAtalhosFocusNode.hasFocus) {
      _listaAtalhosFocusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restaurarSessaoSeHouver();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocusNode.requestFocus();
      if (widget.sessaoCadastro?.carregados.isNotEmpty ?? false) {
        _restaurarScrollSessao();
        return;
      }
      if (widget.sessaoCadastro?.textoPesquisa.trim().isNotEmpty ?? false) {
        unawaited(_executarBuscaTexto(preservarScroll: true));
        return;
      }
      _carregarInicial();
    });
  }

  void _restaurarSessaoSeHouver() {
    final sessao = widget.sessaoCadastro;
    if (sessao == null || !sessao.temEstadoSalvo) return;
    _pesquisaController.text = sessao.textoPesquisa;
    _somenteInativos = sessao.somenteInativos;
    _categoriaFiltro = sessao.categoriaFiltro;
    _ordenacao = sessao.ordenacao;
    _painelDetalheAberto = sessao.painelDetalheAberto;
    if (sessao.carregados.isNotEmpty) {
      _carregados = List<Produto>.from(sessao.carregados);
      _atualizarExibidos(sessao.exibidos);
      _temMaisNoRepo = sessao.temMaisNoRepo;
      _buscaComTexto = sessao.buscaComTexto;
      var indice = sessao.indiceSelecionado;
      if (sessao.produtoIdEmDestaque != null) {
        final porId = _carregados.indexWhere(
          (p) => p.id == sessao.produtoIdEmDestaque,
        );
        if (porId >= 0) indice = porId;
      }
      _exibidosNotifier.value = _exibidos;
      _ajustarSelecaoAposFiltroOuOrdem(
        produtoIdPreservar: sessao.produtoIdEmDestaque ?? 
            (indice >= 0 && indice < sessao.carregados.length
                ? sessao.carregados[indice].id
                : null),
      );
    }
  }

  void _atualizarExibidos(int valor) {
    if (_exibidos == valor) return;
    _exibidos = valor;
    _exibidosNotifier.value = valor;
  }

  void _restaurarScrollSessao() {
    final sessao = widget.sessaoCadastro;
    if (sessao == null || sessao.scrollOffset <= 0) return;
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(
      sessao.scrollOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
    );
  }

  void _persistirSessao({int? produtoIdDestaque}) {
    final sessao = widget.sessaoCadastro;
    if (sessao == null) return;
    sessao.textoPesquisa = _pesquisaController.text;
    sessao.somenteInativos = _somenteInativos;
    sessao.carregados = List<Produto>.from(_carregados);
    sessao.exibidos = _exibidos;
    sessao.indiceSelecionado = _indiceSelecionado.value;
    sessao.temMaisNoRepo = _temMaisNoRepo;
    sessao.buscaComTexto = _buscaComTexto;
    sessao.categoriaFiltro = _categoriaFiltro;
    sessao.ordenacao = _ordenacao;
    sessao.painelDetalheAberto = _painelDetalheAberto;
    sessao.scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : sessao.scrollOffset;
    if (produtoIdDestaque != null) {
      sessao.produtoIdEmDestaque = produtoIdDestaque;
    }
  }

  void _limparPesquisaCadastro() {
    widget.sessaoCadastro?.limpar();
    _debounce?.cancel();
    _pesquisaController.clear();
    setState(() => _somenteInativos = false);
    _reiniciarLista();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _carregarInicial();
  }

  @override
  void dispose() {
    _persistirSessao();
    _debounce?.cancel();
    _debounceCliqueLinha?.cancel();
    _indiceSelecionado.dispose();
    _exibidosNotifier.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    _listaAtalhosFocusNode.dispose();
    super.dispose();
  }

  void _fechar([Produto? produto]) {
    if (_fechando) return;
    _fechando = true;
    _persistirSessao(produtoIdDestaque: produto?.id);
    Navigator.pop(context, produto);
  }

  bool get _termoVazio => _pesquisaController.text.trim().isEmpty;

  void _carregarInicial() {
    unawaited(() async {
      await _garantirCacheApiSeVazio();
      if (!mounted) return;
      _reiniciarLista();
      await _carregarProximaPaginaRepo();
    }());
  }

  void _reiniciarLista() {
    _carregados = [];
    _atualizarExibidos(0);
    _indiceSelecionado.value = -1;
    _temMaisNoRepo = true;
    _buscaComTexto = false;
    _idsMarcados.clear();
  }

  List<Produto> get _visiveis {
    final lista = _listaFiltradaOrdenada;
    final n = math.min(_exibidos, lista.length);
    return lista.take(n).toList();
  }

  bool get _todosVisiveisMarcados {
    final visiveis = _visiveis;
    if (visiveis.isEmpty) return false;
    return visiveis.every((p) => _idsMarcados.contains(p.id));
  }

  bool get _algunsVisiveisMarcados {
    final visiveis = _visiveis;
    if (visiveis.isEmpty) return false;
    final n = visiveis.where((p) => _idsMarcados.contains(p.id)).length;
    return n > 0 && n < visiveis.length;
  }

  void _alternarMarca(int id) {
    setState(() {
      if (_idsMarcados.contains(id)) {
        _idsMarcados.remove(id);
      } else {
        _idsMarcados.add(id);
      }
    });
  }

  void _alternarMarcarTodosVisiveis() {
    setState(() {
      final visiveis = _visiveis;
      if (_todosVisiveisMarcados) {
        for (final p in visiveis) {
          _idsMarcados.remove(p.id);
        }
      } else {
        for (final p in visiveis) {
          _idsMarcados.add(p.id);
        }
      }
    });
  }

  Future<void> _aplicarFotoAosMarcados() async {
    if (_aplicandoFoto || _excluindo || _idsMarcados.isEmpty) return;
    setState(() => _aplicandoFoto = true);
    try {
      final imgSvc = ProdutoImagemService(
        imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
      );
      final origem = await imgSvc.selecionarImagemLocal();
      if (origem == null || !mounted) return;

      final processada = await imgSvc.processarESalvarImagemProduto(
        sourceImagePath: origem,
        productIdentifier: 'lote_${_idsMarcados.length}',
      );
      if (!mounted) return;
      if (processada == null || processada.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel processar a foto selecionada.'),
          ),
        );
        return;
      }

      // Terminal: sobe bytes uma vez antes de gravar o path nos produtos.
      final enviou = await ProdutoImagemLanService(
        imagesDirectoryPath: widget.produtoRepository.productImagesDirPath,
      ).enviarSeRedeAtiva(processada);
      if (!enviou && widget.produtoRepository is ProdutoApiRepository) {
        if (!mounted) return;
        LanApiFeedback.snackAviso(
          context,
          'Foto processada localmente, mas o envio ao servidor falhou.',
          prefixo: 'Foto em lote',
        );
      }

      final ids = _idsMarcados.toList();
      final alteradosRaw = widget.produtoRepository.aplicarFotoEmVarios(
        ids: ids,
        fotoPath: processada,
      );
      final alterados = alteradosRaw is Future
          ? await alteradosRaw as int
          : alteradosRaw as int;
      if (!mounted) return;

      final idsSet = ids.toSet();
      setState(() {
        _carregados = [
          for (final p in _carregados)
            if (idsSet.contains(p.id))
              (p..fotoPath = processada)
            else
              p,
        ];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alterados == 0
                ? 'Nenhum produto teve a foto alterada.'
                : 'Foto aplicada a $alterados produto(s).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Foto em lote');
      }
    } finally {
      if (mounted) setState(() => _aplicandoFoto = false);
    }
  }

  Future<void> _excluirMarcados() async {
    if (_excluindo || _idsMarcados.isEmpty) return;
    final ids = _idsMarcados.toList();
    final nomes = _carregados
        .where((p) => ids.contains(p.id))
        .map((p) => p.nome)
        .take(8)
        .toList();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir ${ids.length} produto(s)?'),
        content: Text(
          'Essa acao nao pode ser desfeita.\n\n'
          '${nomes.map((n) => '• $n').join('\n')}'
          '${ids.length > nomes.length ? '\n• … e mais ${ids.length - nomes.length}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _excluindo = true);
    try {
      final removidosRaw = widget.produtoRepository.removerVarios(ids);
      final removidos = removidosRaw is Future
          ? await removidosRaw as int
          : removidosRaw as int;
      if (!mounted) return;
      setState(() {
        if (removidos > 0) {
          final removidosSet = ids.toSet();
          _carregados =
              _carregados.where((p) => !removidosSet.contains(p.id)).toList();
          _idsMarcados.removeAll(removidosSet);
          _atualizarExibidos(math.min(_exibidos, _carregados.length));
          _ajustarSelecaoAposFiltroOuOrdem(
            produtoIdPreservar: _produtoSelecionado?.id,
          );
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removidos == 0
                ? 'Nenhum produto foi excluido.'
                : '$removidos produto(s) excluido(s).',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Excluir produtos');
      }
    } finally {
      if (mounted) setState(() => _excluindo = false);
    }
  }

  Future<void> _carregarProximaPaginaRepo() async {
    if (_carregando || !_temMaisNoRepo || _buscaComTexto) return;
    setState(() => _carregando = true);
    try {
      await _garantirCacheApiSeVazio();
      if (!mounted) return;
      final raw = await Future.value(
        widget.produtoRepository.pesquisarPaginaCadastro(
          _pesquisaController.text,
          offset: _carregados.length,
          limite: _kLoteRepoVazio,
          somenteAtivos: !_somenteInativos,
          somenteInativos: _somenteInativos,
        ),
      );
      final pagina = reordenarResultadoBuscaProdutos(
        (raw as List).whereType<Produto>(),
        _pesquisaController.text,
      );
      if (!mounted) return;
      setState(() {
        _carregados = reordenarResultadoBuscaProdutos(
          [..._carregados, ...pagina],
          _pesquisaController.text,
        );
        _atualizarExibidos(_carregados.length);
        _temMaisNoRepo = pagina.length >= _kLoteRepoVazio;
        if (_indiceSelecionado.value < 0 && _carregados.isNotEmpty) {
          _indiceSelecionado.value = 0;
        }
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _temMaisNoRepo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar produtos: $e')),
      );
    }
  }

  Future<void> _executarBuscaTexto({bool preservarScroll = false}) async {
    final scrollAntes = preservarScroll && _scrollController.hasClients
        ? _scrollController.offset
        : null;

    if (_termoVazio) {
      _reiniciarLista();
      await _carregarProximaPaginaRepo();
      return;
    }

    _atualizarExibidos(0);
    setState(() {
      _carregando = true;
      _buscaComTexto = true;
      _carregados = [];
      _indiceSelecionado.value = -1;
      _temMaisNoRepo = false;
    });

    try {
      await _garantirCacheApiSeVazio();
      if (!mounted) return;
      final raw = await Future.value(
        widget.produtoRepository.pesquisarPaginaCadastro(
          _pesquisaController.text,
          limite: _kLimiteBuscaTexto,
          somenteAtivos: !_somenteInativos,
          somenteInativos: _somenteInativos,
        ),
      );
      final lista = reordenarResultadoBuscaProdutos(
        (raw as List).whereType<Produto>(),
        _pesquisaController.text,
      );
      if (!mounted) return;
      final destaque = widget.sessaoCadastro?.produtoIdEmDestaque;
      setState(() {
        _carregados = lista;
        _atualizarExibidos(math.min(_kLoteInicialExibicao, lista.length));
        _carregando = false;
      });
      _ajustarSelecaoAposFiltroOuOrdem(
        produtoIdPreservar: destaque ??
            (lista.isNotEmpty ? lista.first.id : null),
      );
      if (scrollAntes != null && _scrollController.hasClients) {
        _scrollController.jumpTo(
          scrollAntes.clamp(0, _scrollController.position.maxScrollExtent),
        );
      } else if (!preservarScroll && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar produtos: $e')),
      );
    }
  }

  /// Terminal leve: pasta de fotos + catalogo se ainda vazio.
  Future<void> _garantirCacheApiSeVazio() async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    try {
      await repo.garantirCacheImagens();
    } catch (_) {}
    if (repo.listarTodos().isNotEmpty) return;
    try {
      await repo.hidratar();
    } catch (_) {}
  }

  void _agendarBusca() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _kDebounceBuscaMs), () {
      if (!mounted) return;
      _executarBuscaTexto();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _carregando) return;
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 96) return;

    final filtrada = _listaFiltradaOrdenada;
    if (_exibidos < filtrada.length) {
      _atualizarExibidos(
        math.min(
          _exibidos + _kLoteScrollExibicao,
          filtrada.length,
        ),
      );
      return;
    }

    if (!_buscaComTexto && _temMaisNoRepo) {
      unawaited(_carregarProximaPaginaRepo());
    }
  }

  double _alturaLinhaLista(bool compacto) =>
      compacto ? _kAlturaLinhaCelular : _kAlturaLinha;

  void _garantirIndiceVisivel() {
    final indice = _indiceSelecionado.value;
    if (indice < 0) return;
    final filtrada = _listaFiltradaOrdenada;
    if (indice >= _exibidos && indice < filtrada.length) {
      _atualizarExibidos(math.min(indice + 1, filtrada.length));
    }
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    final viewport = pos.viewportDimension;
    if (viewport <= 0) return;

    final alturaLinha = _alturaLinhaLista(context.isCompactLayout);
    final itemTop = indice * alturaLinha;
    final itemBottom = itemTop + alturaLinha;
    var alvo = pos.pixels;
    if (itemTop < alvo) {
      alvo = itemTop;
    } else if (itemBottom > alvo + viewport) {
      alvo = itemBottom - viewport;
    } else {
      return;
    }
    alvo = alvo.clamp(0.0, pos.maxScrollExtent);
    if ((alvo - pos.pixels).abs() < 0.5) return;
    _scrollController.jumpTo(alvo);
  }

  void _confirmarSelecionado() {
    final produto = _produtoSelecionado;
    if (produto == null) {
      final lista = _listaFiltradaOrdenada;
      if (lista.isEmpty) return;
      _fechar(lista.first);
      return;
    }
    _fechar(produto);
  }

  void _definirIndiceSelecionado(int indice) {
    if (_indiceSelecionado.value == indice) return;
    _indiceSelecionado.value = indice;
    if (_usarPainelDetalhe && indice >= 0) {
      setState(() => _painelDetalheAberto = true);
    }
  }

  String? _helperBusca() {
    final termo = _pesquisaController.text.trim();
    if (termo.isEmpty) {
      return 'Role a lista para carregar mais produtos aos poucos.';
    }
    final dica = dicaBuscaContextual(termo);
    if (dica != null) return dica;
    if (termo.contains('%')) {
      return 'Trechos: use % entre partes (ex.: tub%sod%25)';
    }
    final parse = tokenizarConsultaObra(termo.toLowerCase());
    if (parse.tokensSignificativos.isNotEmpty) {
      return 'Palavras: ${parse.tokensSignificativos.join(' ')}';
    }
    return null;
  }

  String _rodapeLista() {
    final filtrada = _listaFiltradaOrdenada;
    if (filtrada.isEmpty) {
      if (_carregados.isNotEmpty && _categoriaFiltro.isNotEmpty) {
        return 'Nenhum produto nesta categoria.';
      }
      return _carregando ? 'Buscando...' : 'Nenhum produto encontrado.';
    }
    final totalFiltrado = filtrada.length;
    final visivel = math.min(_exibidos, totalFiltrado);
    final partes = <String>['Exibindo $visivel de $totalFiltrado'];
    if (_categoriaFiltro.isNotEmpty || _carregados.length != totalFiltrado) {
      partes.add('${_carregados.length} carregado(s)');
    }
    if (_buscaComTexto && _carregados.length >= _kLimiteBuscaTexto) {
      partes.add('refine a busca para ver mais');
    } else if (!_buscaComTexto && _temMaisNoRepo) {
      partes.add('role para carregar mais');
    }
    if (_carregando) partes.add('carregando...');
    return partes.join(' · ');
  }

  Widget _filtroCheckbox({
    required bool? value,
    required String rotulo,
    required ValueChanged<bool?> onChanged,
    bool tristate = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          width: 28,
          child: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            tristate: tristate,
            value: value,
            onChanged: onChanged,
          ),
        ),
        Text(
          rotulo,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildListaProdutos({
    required int itemCount,
    required bool compacto,
  }) {
    if (itemCount == 0) {
      return Center(child: Text(_rodapeLista()));
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: !compacto,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: itemCount + (_carregando ? 1 : 0),
        itemExtent: _alturaLinhaLista(compacto),
        addRepaintBoundaries: false,
        cacheExtent: compacto ? 200 : 320,
        itemBuilder: (context, index) {
          if (index >= itemCount) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final produto = _listaFiltradaOrdenada[index];
          return RepaintBoundary(
            key: ValueKey<int>(produto.id),
            child: _ProdutoPesquisaLinha(
              produto: produto,
              consulta: _pesquisaController.text.trim(),
              indice: index,
              indiceSelecionado: _indiceSelecionado,
              marcado: _idsMarcados.contains(produto.id),
              compacto: compacto,
              imagesDirectoryPath:
                  widget.produtoRepository.productImagesDirPath,
              onToggleMarca: () => _alternarMarca(produto.id),
              onTap: () => _onLinhaTap(index, produto),
              onDoubleTap: () => _onLinhaDuploClique(index, produto),
              onHover: () => _definirIndiceSelecionado(index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAreaLista({required bool compacto}) {
    return ValueListenableBuilder<int>(
      valueListenable: _exibidosNotifier,
      builder: (context, exibidos, _) {
        final itemCount = math.min(exibidos, _listaFiltradaOrdenada.length);
        return _buildListaProdutos(
          itemCount: itemCount,
          compacto: compacto,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final compacto = context.isCompactLayout;
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final alturaPainel =
        mq.size.height - mq.viewInsets.bottom - mq.padding.top;

    final filtros = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filtroCheckbox(
          value: _somenteInativos,
          rotulo: 'Somente inativos',
          onChanged: (v) {
            if (v == null) return;
            setState(() => _somenteInativos = v);
            _debounce?.cancel();
            unawaited(_executarBuscaTexto());
          },
        ),
        if (_visiveis.isNotEmpty)
          _filtroCheckbox(
            tristate: true,
            value: _todosVisiveisMarcados
                ? true
                : (_algunsVisiveisMarcados ? null : false),
            rotulo: 'Marcar exibidos',
            onChanged: (_) => _alternarMarcarTodosVisiveis(),
          ),
      ],
    );

    var categorias = _categoriasParaFiltro();
    if (_categoriaFiltro.isNotEmpty && !categorias.contains(_categoriaFiltro)) {
      categorias = [...categorias, _categoriaFiltro]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    Widget campoBusca({String? helper}) {
      return TextField(
        controller: _pesquisaController,
        focusNode: _pesquisaFocusNode,
        autofocus: true,
        decoration: produtoBuscaInputDecoration(
          helperText: helper,
          suffixIcon: widget.sessaoCadastro != null &&
                  _pesquisaController.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Limpar busca',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _limparPesquisaCadastro,
                )
              : null,
        ),
        onChanged: (_) {
          setState(() {});
          _agendarBusca();
        },
        onSubmitted: (_) => _confirmarSelecionado(),
      );
    }

    final filtroCategoria = DropdownButtonFormField<String>(
      value: _categoriaFiltro.isEmpty ? _kTodasCategorias : _categoriaFiltro,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Categoria',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem(
          value: _kTodasCategorias,
          child: Text('Todas as categorias'),
        ),
        for (final cat in categorias)
          DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (valor) {
        if (valor == null) return;
        final idPreservar = _produtoSelecionado?.id;
        setState(() => _categoriaFiltro = valor);
        _ajustarSelecaoAposFiltroOuOrdem(produtoIdPreservar: idPreservar);
      },
    );

    final botaoOrdenacao = Tooltip(
      message: 'Ordenacao: ${_ordenacao.rotulo}',
      child: PopupMenuButton<ProdutoPesquisaOrdenacao>(
        tooltip: 'Ordenar lista',
        icon: const Icon(Icons.sort),
        initialValue: _ordenacao,
        onSelected: (ordem) {
          final idPreservar = _produtoSelecionado?.id;
          setState(() => _ordenacao = ordem);
          _ajustarSelecaoAposFiltroOuOrdem(produtoIdPreservar: idPreservar);
        },
        itemBuilder: (ctx) => [
          for (final ordem in ProdutoPesquisaOrdenacao.values)
            PopupMenuItem(
              value: ordem,
              child: Row(
                children: [
                  if (ordem == _ordenacao)
                    Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ordem.rotulo)),
                ],
              ),
            ),
        ],
      ),
    );

    final barraBusca = compacto
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              campoBusca(helper: _helperBusca()),
              const SizedBox(height: 8),
              filtroCategoria,
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: botaoOrdenacao),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: campoBusca(helper: _helperBusca())),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: filtroCategoria),
              const SizedBox(width: 4),
              botaoOrdenacao,
            ],
          );

    final rodape = ValueListenableBuilder<int>(
      valueListenable: _exibidosNotifier,
      builder: (context, _exibidosListen, _child) {
        return Text(
          _idsMarcados.isEmpty
              ? _rodapeLista()
              : '${_rodapeLista()} · ${_idsMarcados.length} marcado(s)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        );
      },
    );

    final acoes = [
      if (_idsMarcados.isNotEmpty) ...[
        Tooltip(
          message: 'Aplicar a mesma foto a todos os produtos marcados',
          child: TextButton.icon(
            onPressed:
                (_excluindo || _aplicandoFoto) ? null : _aplicarFotoAosMarcados,
            icon: _aplicandoFoto
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_outlined, size: 18),
            label: const Text('Foto'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: (_excluindo || _aplicandoFoto) ? null : _excluirMarcados,
          icon: _excluindo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline),
          label: Text('Excluir ${_idsMarcados.length}'),
          style: FilledButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
        ),
      ],
      TextButton(
        onPressed: (_excluindo || _aplicandoFoto) ? null : _fechar,
        child: const Text('Fechar'),
      ),
    ];

    return Focus(
      focusNode: _listaAtalhosFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_usarPainelDetalhe && _painelDetalheAberto) {
            _fecharPainelDetalhe();
            return KeyEventResult.handled;
          }
          _fechar();
          return KeyEventResult.handled;
        }
        final totalLista = _listaFiltradaOrdenada.length;
        if (totalLista == 0) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _ativarFocoAtalhosLista();
          _definirIndiceSelecionado(math.min(
            (_indiceSelecionado.value < 0 ? 0 : _indiceSelecionado.value + 1),
            totalLista - 1,
          ));
          _garantirIndiceVisivel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _ativarFocoAtalhosLista();
          _definirIndiceSelecionado(
            math.max(_indiceSelecionado.value - 1, 0),
          );
          _garantirIndiceVisivel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _confirmarSelecionado();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: theme.colorScheme.surface,
        child: SizedBox(
          width: mq.size.width,
          height: alturaPainel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  _kMargemDialogo,
                  mq.padding.top + (compacto ? 10 : 12),
                  _kMargemDialogo,
                  8,
                ),
                child: Text(
                  'Pesquisar produto',
                  style: compacto
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall,
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  _kMargemDialogo,
                  10,
                  _kMargemDialogo,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    filtros,
                    const SizedBox(height: 6),
                    barraBusca,
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!compacto)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kMargemDialogo,
                                ),
                                child: Builder(
                                  builder: (ctx) {
                                    final cor = Theme.of(ctx)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.55);
                                    return DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: cor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const _ProdutoPesquisaCabecalho(),
                                          Expanded(
                                            child: _buildAreaLista(
                                              compacto: compacto,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: _buildAreaLista(compacto: compacto),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_usarPainelDetalhe &&
                        _painelDetalheAberto &&
                        _produtoSelecionado != null)
                      ValueListenableBuilder<int>(
                        valueListenable: _indiceSelecionado,
                        builder: (context, _, __) {
                          final produto = _produtoSelecionado;
                          if (produto == null) return const SizedBox.shrink();
                          return _ProdutoPesquisaDetalhePanel(
                            produto: produto,
                            imagesDirectoryPath:
                                widget.produtoRepository.productImagesDirPath,
                            onFechar: _fecharPainelDetalhe,
                            onEditar: () => _fechar(produto),
                          );
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  _kMargemDialogo,
                  6,
                  _kMargemDialogo,
                  math.max(mq.padding.bottom, 8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BarraAtalhosPesquisaProduto(compacto: compacto),
                    const SizedBox(height: 6),
                    rodape,
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: acoes,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoPesquisaCabecalho extends StatelessWidget {
  const _ProdutoPesquisaCabecalho();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estilo = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: SizedBox(
        height: _kAlturaCabecalhoGrade,
        child: _ProdutoPesquisaGridRow(
          bordaInferior: true,
          marcacao: const SizedBox.shrink(),
          foto: const SizedBox.shrink(),
          codigo: Text('Codigo', style: estilo),
          descricao: Text('Descricao', style: estilo),
          unidade: Text('Un.', style: estilo, textAlign: TextAlign.center),
          preco1: Text('Preco 1', style: estilo, textAlign: TextAlign.end),
          preco2: Text('Preco 2', style: estilo, textAlign: TextAlign.end),
          estoque: Text('Estoque', style: estilo, textAlign: TextAlign.end),
          categoria: Text('Categoria', style: estilo),
        ),
      ),
    );
  }
}

/// Grade alinhada (cabecalho + linhas) com divisores verticais em cada coluna.
class _ProdutoPesquisaGridRow extends StatelessWidget {
  const _ProdutoPesquisaGridRow({
    required this.marcacao,
    required this.foto,
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.preco1,
    required this.preco2,
    required this.estoque,
    required this.categoria,
    this.bordaInferior = false,
  });

  final Widget marcacao;
  final Widget foto;
  final Widget codigo;
  final Widget descricao;
  final Widget unidade;
  final Widget preco1;
  final Widget preco2;
  final Widget estoque;
  final Widget categoria;
  final bool bordaInferior;

  static Color _corBorda(BuildContext context) {
    return Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55);
  }

  Widget _celula(
    BuildContext context, {
    required Widget child,
    required double largura,
    Alignment alignment = Alignment.centerLeft,
    bool ultimaColuna = false,
  }) {
    return SizedBox(
      width: largura,
      child: Container(
        alignment: alignment,
        padding: _ProdutoPesquisaColunas.paddingCelula,
        decoration: BoxDecoration(
          border: Border(
            right: ultimaColuna
                ? BorderSide.none
                : BorderSide(color: _corBorda(context)),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _celulaFlex(
    BuildContext context, {
    required Widget child,
    required int flex,
    Alignment alignment = Alignment.centerLeft,
    bool ultimaColuna = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: alignment,
        padding: _ProdutoPesquisaColunas.paddingCelula,
        decoration: BoxDecoration(
          border: Border(
            right: ultimaColuna
                ? BorderSide.none
                : BorderSide(color: _corBorda(context)),
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borda = _corBorda(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: bordaInferior
            ? Border(bottom: BorderSide(color: borda))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraMarcacao,
            alignment: Alignment.center,
            child: marcacao,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraFoto,
            alignment: Alignment.center,
            child: foto,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraCodigo,
            child: codigo,
          ),
          _celulaFlex(
            context,
            flex: _ProdutoPesquisaColunas.flexDescricao,
            child: descricao,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraUnidade,
            alignment: Alignment.center,
            child: unidade,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraPrecoColuna,
            alignment: Alignment.centerRight,
            child: preco1,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraPrecoColuna,
            alignment: Alignment.centerRight,
            child: preco2,
          ),
          _celula(
            context,
            largura: _ProdutoPesquisaColunas.larguraEstoque,
            alignment: Alignment.centerRight,
            child: estoque,
          ),
          _celulaFlex(
            context,
            flex: _ProdutoPesquisaColunas.flexCategoria,
            ultimaColuna: true,
            child: categoria,
          ),
        ],
      ),
    );
  }
}

class _ProdutoPesquisaCategoriaChip extends StatelessWidget {
  const _ProdutoPesquisaCategoriaChip({
    required this.rotulo,
    required this.consulta,
  });

  final String rotulo;
  final String consulta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rotulo == '-') {
      return Text(
        '-',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minHeight: 18, maxHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: _TextoComDestaque(
          texto: rotulo,
          termo: consulta,
          estilo: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSecondaryContainer,
              ) ??
              const TextStyle(fontWeight: FontWeight.w600),
          maxLinhas: 1,
        ),
      ),
    );
  }
}

class _ProdutoPesquisaLinha extends StatelessWidget {
  const _ProdutoPesquisaLinha({
    required this.produto,
    required this.consulta,
    required this.indice,
    required this.indiceSelecionado,
    required this.marcado,
    this.compacto = false,
    required this.imagesDirectoryPath,
    required this.onToggleMarca,
    required this.onTap,
    required this.onDoubleTap,
    required this.onHover,
  });

  final Produto produto;
  final String consulta;
  final int indice;
  final ValueNotifier<int> indiceSelecionado;
  final bool marcado;
  final bool compacto;
  final String imagesDirectoryPath;
  final VoidCallback onToggleMarca;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estiloTitulo = (compacto
                ? Theme.of(context).textTheme.titleSmall
                : Theme.of(context).textTheme.labelLarge)
            ?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.05,
              fontSize: 12.5,
            ) ??
        const TextStyle(fontWeight: FontWeight.w600, height: 1.05);
    final estiloSubtitulo = compacto
        ? (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        : (Theme.of(context).textTheme.bodyMedium ?? const TextStyle());
    final subtitulo = compacto
        ? '${produto.codigoInterno} · '
            '${rotuloUnidadeProdutoLista(produto)}'
            '${produto.categoria.isEmpty ? '' : ' · ${produto.categoria}'}'
            '${produto.ativo ? '' : ' · Inativo'}'
        : 'SKU: ${produto.codigoInterno} | '
            'Un: ${rotuloUnidadeProdutoLista(produto)} | '
            'Categoria: ${produto.categoria.isEmpty ? '-' : produto.categoria}'
            '${produto.ativo ? '' : ' · Inativo'}';

    final foto = _ProdutoFotoMiniatura(
      key: ValueKey<String>('foto-${produto.id}-${produto.fotoPath}'),
      fotoPath: produto.fotoPath,
      imagesDirectoryPath: imagesDirectoryPath,
    );

    return ValueListenableBuilder<int>(
      valueListenable: indiceSelecionado,
      builder: (context, indiceSel, _) {
        final selecionado = indiceSel == indice;
        final fundoSelecionado = marcado
            ? scheme.error.withValues(alpha: 0.08)
            : scheme.primary.withValues(alpha: 0.08);

        if (!compacto) {
          final estiloCelula = Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.05,
                fontSize: 11.5,
              );
          final codigo = produto.codigoInterno.trim().isEmpty
              ? '-'
              : produto.codigoInterno.trim();
          final categoria = produto.categoria.trim().isEmpty
              ? '-'
              : produto.categoria.trim();
          final preco1Txt =
              'R\$ ${_moedaListaProduto.format(produto.preco1)}';
          final preco2Txt =
              'R\$ ${_moedaListaProduto.format(produto.preco2)}';
          final estiloPreco =
              estiloCelula?.copyWith(fontWeight: FontWeight.w600);
          final zebra = indice.isOdd
              ? scheme.surfaceContainerLowest.withValues(alpha: 0.35)
              : Colors.transparent;
          final fundo = (selecionado || marcado) ? fundoSelecionado : zebra;
          return MouseRegion(
            onEnter: (_) => onHover(),
            child: Material(
              color: fundo,
              child: InkWell(
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                onLongPress: onToggleMarca,
                child: SizedBox(
                  height: _kAlturaLinha,
                  child: _ProdutoPesquisaGridRow(
                    bordaInferior: true,
                    marcacao: SizedBox(
                      height: _kAlturaLinha,
                      child: Center(
                        child: Transform.scale(
                          scale: 0.82,
                          child: Checkbox(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            value: marcado,
                            onChanged: (_) => onToggleMarca(),
                          ),
                        ),
                      ),
                    ),
                    foto: foto,
                    codigo: _TextoComDestaque(
                      texto: codigo,
                      termo: consulta,
                      estilo: estiloCelula ?? estiloSubtitulo,
                      maxLinhas: 1,
                    ),
                    descricao: _TextoComDestaque(
                      texto: produto.ativo
                          ? produto.nome
                          : '${produto.nome} (Inativo)',
                      termo: consulta,
                      estilo: estiloTitulo,
                      maxLinhas: 1,
                    ),
                    unidade: Text(
                      rotuloUnidadeProdutoLista(produto),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: estiloCelula?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    preco1: Text(
                      preco1Txt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: estiloPreco,
                    ),
                    preco2: Text(
                      preco2Txt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: estiloPreco,
                    ),
                    estoque: SizedBox(
                      height: _kAlturaLinha,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PdvConsultaSemaforoEstoque(
                          produto: produto,
                          compacto: true,
                        ),
                      ),
                    ),
                    categoria: _ProdutoPesquisaCategoriaChip(
                      rotulo: categoria,
                      consulta: consulta,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => onHover(),
          child: Material(
            color: (selecionado || marcado) ? fundoSelecionado : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              onLongPress: onToggleMarca,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                selected: selecionado || marcado,
                selectedTileColor: Colors.transparent,
                leading: foto,
                title: _TextoComDestaque(
                  texto: produto.nome,
                  termo: consulta,
                  estilo: estiloTitulo,
                  maxLinhas: 1,
                ),
                subtitle: _TextoComDestaque(
                  texto: subtitulo,
                  termo: consulta,
                  estilo: estiloSubtitulo,
                  maxLinhas: 1,
                ),
                trailing: Checkbox(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  value: marcado,
                  onChanged: (_) => onToggleMarca(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Miniatura 40px: no celular so local (evita HTTP em massa); no PC/terminal baixa da API.
class _ProdutoFotoMiniatura extends StatelessWidget {
  const _ProdutoFotoMiniatura({
    super.key,
    required this.fotoPath,
    required this.imagesDirectoryPath,
  });

  final String fotoPath;
  final String imagesDirectoryPath;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (_kMiniaturaPx * dpr).round().clamp(24, 64);
    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    return SizedBox(
      width: _kMiniaturaPx,
      height: _kMiniaturaPx,
      child: ProdutoFotoView(
        fotoPath: fotoPath,
        imagesDirectoryPath: imagesDirectoryPath,
        width: _kMiniaturaPx,
        height: _kMiniaturaPx,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(6),
        placeholderLabel: '',
        errorLabel: '',
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        filterQuality: FilterQuality.low,
        modo: celular
            ? ProdutoFotoModo.somenteLocal
            : ProdutoFotoModo.automatico,
      ),
    );
  }
}

class _TextoComDestaque extends StatelessWidget {
  const _TextoComDestaque({
    required this.texto,
    required this.termo,
    required this.estilo,
    this.maxLinhas = 2,
  });

  final String texto;
  final String termo;
  final TextStyle estilo;
  final int maxLinhas;

  @override
  Widget build(BuildContext context) {
    final busca = termo.trim().toLowerCase();
    if (busca.isEmpty) {
      return Text(
        texto,
        style: estilo,
        maxLines: maxLinhas,
        overflow: TextOverflow.ellipsis,
      );
    }

    final textoMinusculo = texto.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    final destaque = estilo.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );

    while (cursor < texto.length) {
      final indice = textoMinusculo.indexOf(busca, cursor);
      if (indice < 0) {
        spans.add(TextSpan(text: texto.substring(cursor)));
        break;
      }
      if (indice > cursor) {
        spans.add(TextSpan(text: texto.substring(cursor, indice)));
      }
      spans.add(
        TextSpan(
          text: texto.substring(indice, indice + busca.length),
          style: destaque,
        ),
      );
      cursor = indice + busca.length;
    }

    return RichText(
      maxLines: maxLinhas,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: estilo, children: spans),
    );
  }
}

class _BarraAtalhosPesquisaProduto extends StatelessWidget {
  const _BarraAtalhosPesquisaProduto({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.1,
        );
    final partes = compacto
        ? '[Enter] Selecionar · [Esc] Sair'
        : '[↑↓] Navegar · [Enter] Selecionar · [2× clique] Confirmar · [Esc] Sair';
    return Text(partes, style: estilo);
  }
}

class _ProdutoPesquisaDetalhePanel extends StatelessWidget {
  const _ProdutoPesquisaDetalhePanel({
    required this.produto,
    required this.imagesDirectoryPath,
    required this.onFechar,
    required this.onEditar,
  });

  final Produto produto;
  final String imagesDirectoryPath;
  final VoidCallback onFechar;
  final VoidCallback onEditar;

  String _moeda(double v) => 'R\$ ${_moedaListaProduto.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ean = produto.codigoBarras.trim();
    final fornecedor = produto.fornecedor.trim();
    final categoria = produto.categoria.trim();

    return Material(
      elevation: 2,
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: _kLarguraPainelDetalhe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalhes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recolher painel (Esc)',
                    onPressed: onFechar,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: produto.fotoPath.trim().isEmpty
                            ? Container(
                                width: 160,
                                height: 160,
                                color: scheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  size: 48,
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : ProdutoFotoView(
                                fotoPath: produto.fotoPath,
                                imagesDirectoryPath: imagesDirectoryPath,
                                width: 160,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      produto.nome,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU ${produto.codigoInterno.trim().isEmpty ? '-' : produto.codigoInterno.trim()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _DetalheSecaoTitulo(titulo: 'Codigo de barras (EAN)'),
                    Text(
                      ean.isEmpty ? 'Nao informado' : ean,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    _DetalheSecaoTitulo(titulo: 'Precos'),
                    _DetalheLinhaValor(
                      rotulo: 'Preco 1',
                      valor: _moeda(produto.preco1),
                    ),
                    _DetalheLinhaValor(
                      rotulo: 'Preco 2',
                      valor: _moeda(produto.preco2),
                    ),
                    _DetalheLinhaValor(
                      rotulo: 'Custo medio',
                      valor: _moeda(produto.custoMedio),
                    ),
                    const SizedBox(height: 14),
                    _DetalheSecaoTitulo(titulo: 'Estoque'),
                    PdvEstoqueResumoPanel(produto: produto, compacto: true),
                    const SizedBox(height: 14),
                    _DetalheSecaoTitulo(titulo: 'Fornecedor e categoria'),
                    _DetalheLinhaValor(
                      rotulo: 'Fornecedor',
                      valor: fornecedor.isEmpty ? '-' : fornecedor,
                    ),
                    _DetalheLinhaValor(
                      rotulo: 'Categoria',
                      valor: categoria.isEmpty ? '-' : categoria,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: FilledButton.icon(
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Editar produto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetalheSecaoTitulo extends StatelessWidget {
  const _DetalheSecaoTitulo({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _DetalheLinhaValor extends StatelessWidget {
  const _DetalheLinhaValor({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              rotulo,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

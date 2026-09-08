import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api/produto_api_repository.dart';
import '../../data/produto_busca_util.dart';
import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../../services/produto_imagem_lan_service.dart';
import '../../services/produto_imagem_service.dart';
import '../layout/app_layout.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/produto_busca_input.dart';
import '../widgets/produto_foto_view.dart';

const int _kLoteInicialExibicao = 35;
const int _kLoteScrollExibicao = 35;
const int _kLoteRepoVazio = 40;
const int _kLimiteBuscaTexto = 350;
const int _kDebounceBuscaMs = 260;
const double _kAlturaLinha = 68.0;
const double _kMiniaturaPx = 40.0;

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

  bool get temEstadoSalvo =>
      textoPesquisa.trim().isNotEmpty ||
      carregados.isNotEmpty ||
      somenteInativos;

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
  Timer? _debounce;

  var _somenteInativos = false;
  var _carregados = <Produto>[];
  var _exibidos = 0;
  final ValueNotifier<int> _indiceSelecionado = ValueNotifier(-1);
  var _temMaisNoRepo = true;
  var _carregando = false;
  var _buscaComTexto = false;
  var _fechando = false;
  final _idsMarcados = <int>{};
  var _excluindo = false;
  var _aplicandoFoto = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _restaurarSessaoSeHouver();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    if (sessao.carregados.isNotEmpty) {
      _carregados = List<Produto>.from(sessao.carregados);
      _exibidos = sessao.exibidos;
      _temMaisNoRepo = sessao.temMaisNoRepo;
      _buscaComTexto = sessao.buscaComTexto;
      var indice = sessao.indiceSelecionado;
      if (sessao.produtoIdEmDestaque != null) {
        final porId = _carregados.indexWhere(
          (p) => p.id == sessao.produtoIdEmDestaque,
        );
        if (porId >= 0) indice = porId;
      }
      _indiceSelecionado.value = indice;
    }
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
    _indiceSelecionado.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
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
    _exibidos = 0;
    _indiceSelecionado.value = -1;
    _temMaisNoRepo = true;
    _buscaComTexto = false;
    _idsMarcados.clear();
  }

  List<Produto> get _visiveis {
    final n = math.min(_exibidos, _carregados.length);
    return _carregados.take(n).toList();
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
          _exibidos = math.min(_exibidos, _carregados.length);
          if (_indiceSelecionado.value >= _carregados.length) {
            _indiceSelecionado.value =
                _carregados.isEmpty ? -1 : _carregados.length - 1;
          }
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
      final pagina = (raw as List).whereType<Produto>().toList();
      if (!mounted) return;
      setState(() {
        _carregados = [..._carregados, ...pagina];
        _exibidos = _carregados.length;
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

    setState(() {
      _carregando = true;
      _buscaComTexto = true;
      _carregados = [];
      _exibidos = 0;
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
      final lista = (raw as List).whereType<Produto>().toList();
      if (!mounted) return;
      setState(() {
        _carregados = lista;
        _exibidos = math.min(_kLoteInicialExibicao, lista.length);
        final destaque = widget.sessaoCadastro?.produtoIdEmDestaque;
        if (destaque != null) {
          final idx = lista.indexWhere((p) => p.id == destaque);
          _indiceSelecionado.value = idx >= 0 ? idx : (lista.isEmpty ? -1 : 0);
        } else {
          _indiceSelecionado.value = lista.isEmpty ? -1 : 0;
        }
        _carregando = false;
      });
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

    if (_exibidos < _carregados.length) {
      setState(() {
        _exibidos = math.min(
          _exibidos + _kLoteScrollExibicao,
          _carregados.length,
        );
      });
      return;
    }

    if (!_buscaComTexto && _temMaisNoRepo) {
      unawaited(_carregarProximaPaginaRepo());
    }
  }

  void _garantirIndiceVisivel() {
    final indice = _indiceSelecionado.value;
    if (indice < 0) return;
    if (indice >= _exibidos && indice < _carregados.length) {
      setState(() {
        _exibidos = math.min(
          indice + 1,
          _carregados.length,
        );
      });
    }
    if (!_scrollController.hasClients) return;
    if (context.isCompactLayout) return;
    final alvo = (indice * _kAlturaLinha).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      alvo,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _confirmarSelecionado() {
    if (_carregados.isEmpty) return;
    final indice = _indiceSelecionado.value >= 0 ? _indiceSelecionado.value : 0;
    _fechar(_carregados[indice]);
  }

  void _definirIndiceSelecionado(int indice) {
    if (_indiceSelecionado.value == indice) return;
    _indiceSelecionado.value = indice;
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
    if (_carregados.isEmpty) {
      return _carregando ? 'Buscando...' : 'Nenhum produto encontrado.';
    }
    final totalCarregado = _carregados.length;
    final visivel = math.min(_exibidos, totalCarregado);
    final partes = <String>['Exibindo $visivel de $totalCarregado'];
    if (_buscaComTexto && totalCarregado >= _kLimiteBuscaTexto) {
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
        itemExtent: compacto ? null : _kAlturaLinha,
        addRepaintBoundaries: true,
        cacheExtent: compacto ? 160 : 280,
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
          final produto = _carregados[index];
          return _ProdutoPesquisaLinha(
            produto: produto,
            consulta: _pesquisaController.text.trim(),
            indice: index,
            indiceSelecionado: _indiceSelecionado,
            marcado: _idsMarcados.contains(produto.id),
            compacto: compacto,
            imagesDirectoryPath:
                widget.produtoRepository.productImagesDirPath,
            onToggleMarca: () => _alternarMarca(produto.id),
            onTap: () => _fechar(produto),
            onHover: () => _definirIndiceSelecionado(index),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compacto = context.isCompactLayout;
    final mq = MediaQuery.of(context);
    final itemCount = math.min(_exibidos, _carregados.length);
    final alturaListaDesktop = adaptiveDialogListMaxHeight(context);
    final alturaPainelCelular = (mq.size.height -
            mq.viewInsets.bottom -
            mq.padding.vertical -
            148)
        .clamp(240.0, mq.size.height);

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

    final campoBusca = TextField(
      controller: _pesquisaController,
      focusNode: _pesquisaFocusNode,
      autofocus: !compacto,
      decoration: produtoBuscaInputDecoration(
        helperText: compacto ? null : _helperBusca(),
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

    final rodape = Text(
      _idsMarcados.isEmpty
          ? _rodapeLista()
          : '${_rodapeLista()} · ${_idsMarcados.length} marcado(s)',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );

    final corpo = compacto
        ? SizedBox(
            height: alturaPainelCelular,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtros,
                const SizedBox(height: 6),
                campoBusca,
                const SizedBox(height: 8),
                Expanded(
                  child: _buildListaProdutos(
                    itemCount: itemCount,
                    compacto: true,
                  ),
                ),
                const SizedBox(height: 6),
                rodape,
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              filtros,
              const SizedBox(height: 6),
              campoBusca,
              const SizedBox(height: 8),
              SizedBox(
                height: alturaListaDesktop,
                child: _buildListaProdutos(
                  itemCount: itemCount,
                  compacto: false,
                ),
              ),
              const SizedBox(height: 6),
              rodape,
            ],
          );

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || _carregados.isEmpty) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _definirIndiceSelecionado(math.min(
            _indiceSelecionado.value + 1,
            _carregados.length - 1,
          ));
          _garantirIndiceVisivel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _definirIndiceSelecionado(math.max(_indiceSelecionado.value - 1, 0));
          _garantirIndiceVisivel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _confirmarSelecionado();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _fechar();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        insetPadding: compacto
            ? const EdgeInsets.fromLTRB(8, 12, 8, 12)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        titlePadding: compacto
            ? const EdgeInsets.fromLTRB(16, 14, 16, 8)
            : null,
        contentPadding: compacto
            ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
            : null,
        title: const Text('Pesquisar produto'),
        content: AdaptiveDialogPane(
          desktopWidth: 760,
          horizontalMargin: compacto ? 8 : 24,
          child: corpo,
        ),
        actionsPadding: compacto
            ? const EdgeInsets.fromLTRB(12, 0, 12, 10)
            : null,
        actions: [
          if (_idsMarcados.isNotEmpty) ...[
            Tooltip(
              message: 'Aplicar a mesma foto a todos os produtos marcados',
              child: TextButton.icon(
                onPressed: (_excluindo || _aplicandoFoto)
                    ? null
                    : _aplicarFotoAosMarcados,
                icon: _aplicandoFoto
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_outlined, size: 18),
                label: const Text('Foto'),
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
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
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          TextButton(
            onPressed: (_excluindo || _aplicandoFoto) ? null : _fechar,
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _ProdutoPesquisaLinha extends StatefulWidget {
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
  final VoidCallback onHover;

  @override
  State<_ProdutoPesquisaLinha> createState() => _ProdutoPesquisaLinhaState();
}

class _ProdutoPesquisaLinhaState extends State<_ProdutoPesquisaLinha> {
  late bool _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.indiceSelecionado.value == widget.indice;
    widget.indiceSelecionado.addListener(_aoMudarSelecao);
  }

  @override
  void didUpdateWidget(covariant _ProdutoPesquisaLinha oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indiceSelecionado != widget.indiceSelecionado) {
      oldWidget.indiceSelecionado.removeListener(_aoMudarSelecao);
      widget.indiceSelecionado.addListener(_aoMudarSelecao);
    }
    final agora = widget.indiceSelecionado.value == widget.indice;
    if (agora != _selecionado) {
      _selecionado = agora;
    }
  }

  @override
  void dispose() {
    widget.indiceSelecionado.removeListener(_aoMudarSelecao);
    super.dispose();
  }

  void _aoMudarSelecao() {
    final agora = widget.indiceSelecionado.value == widget.indice;
    if (agora == _selecionado) return;
    setState(() => _selecionado = agora);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compacto = widget.compacto;
    final estiloTitulo = (compacto
                ? Theme.of(context).textTheme.titleSmall
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(fontWeight: FontWeight.w600) ??
        const TextStyle(fontWeight: FontWeight.w600);
    final estiloSubtitulo = compacto
        ? (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        : (Theme.of(context).textTheme.bodyMedium ?? const TextStyle());
    final subtitulo = compacto
        ? '${widget.produto.codigoInterno} · '
            '${rotuloUnidadeProdutoLista(widget.produto)}'
            '${widget.produto.categoria.isEmpty ? '' : ' · ${widget.produto.categoria}'}'
            '${widget.produto.ativo ? '' : ' · Inativo'}'
        : 'SKU: ${widget.produto.codigoInterno} | '
            'Un: ${rotuloUnidadeProdutoLista(widget.produto)} | '
            'Categoria: ${widget.produto.categoria.isEmpty ? '-' : widget.produto.categoria}'
            '${widget.produto.ativo ? '' : ' · Inativo'}';

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => widget.onHover(),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: compacto ? 6 : 4,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compacto ? 4 : 6,
            vertical: compacto ? 4 : 2,
          ),
          selected: _selecionado || widget.marcado,
          selectedTileColor: widget.marcado
              ? scheme.error.withValues(alpha: 0.08)
              : scheme.primary.withValues(alpha: 0.08),
          leading: _ProdutoFotoMiniatura(
            fotoPath: widget.produto.fotoPath,
            imagesDirectoryPath: widget.imagesDirectoryPath,
          ),
          title: _TextoComDestaque(
            texto: widget.produto.nome,
            termo: widget.consulta,
            estilo: estiloTitulo,
            maxLinhas: compacto ? 2 : 2,
          ),
          subtitle: _TextoComDestaque(
            texto: subtitulo,
            termo: widget.consulta,
            estilo: estiloSubtitulo,
            maxLinhas: compacto ? 2 : 2,
          ),
          trailing: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            value: widget.marcado,
            onChanged: (_) => widget.onToggleMarca(),
          ),
          onTap: widget.onTap,
          onLongPress: widget.onToggleMarca,
        ),
      ),
    );
  }
}

/// Miniatura 40px: no celular so local (evita HTTP em massa); no PC/terminal baixa da API.
class _ProdutoFotoMiniatura extends StatelessWidget {
  const _ProdutoFotoMiniatura({
    required this.fotoPath,
    required this.imagesDirectoryPath,
  });

  final String fotoPath;
  final String imagesDirectoryPath;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (_kMiniaturaPx * dpr).round().clamp(40, 96);
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

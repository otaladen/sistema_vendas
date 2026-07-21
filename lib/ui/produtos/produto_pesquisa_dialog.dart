import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/produto_busca_util.dart';
import '../../data/produto_repository.dart';
import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../../services/produto_imagem_service.dart';
import '../layout/app_layout.dart';
import '../widgets/produto_busca_input.dart';
import '../widgets/produto_foto_view.dart';

const int _kLoteInicialExibicao = 35;
const int _kLoteScrollExibicao = 35;
const int _kLoteRepoVazio = 40;
const int _kLimiteBuscaTexto = 350;
const int _kDebounceBuscaMs = 260;
const double _kAlturaLinha = 68.0;
const double _kMiniaturaPx = 40.0;

/// Dialogo de pesquisa de produto no cadastro (debounce + scroll progressivo).
Future<Produto?> showProdutoPesquisaDialog({
  required BuildContext context,
  required ProdutoRepository produtoRepository,
}) {
  return showDialog<Produto>(
    context: context,
    builder: (context) => _ProdutoPesquisaDialog(
      produtoRepository: produtoRepository,
    ),
  );
}

class _ProdutoPesquisaDialog extends StatefulWidget {
  const _ProdutoPesquisaDialog({required this.produtoRepository});

  final ProdutoRepository produtoRepository;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _carregarInicial();
    });
  }

  @override
  void dispose() {
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
    Navigator.pop(context, produto);
  }

  bool get _termoVazio => _pesquisaController.text.trim().isEmpty;

  void _carregarInicial() {
    _reiniciarLista();
    _carregarProximaPaginaRepo();
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

      final ids = _idsMarcados.toList();
      final alterados = widget.produtoRepository.aplicarFotoEmVarios(
        ids: ids,
        fotoPath: processada,
      );
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
    final removidos = widget.produtoRepository.removerVarios(ids);
    if (!mounted) return;
    setState(() {
      _excluindo = false;
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
  }

  Future<void> _carregarProximaPaginaRepo() async {
    if (_carregando || !_temMaisNoRepo || _buscaComTexto) return;
    setState(() => _carregando = true);

    final pagina = widget.produtoRepository.pesquisarPaginaCadastro(
      _pesquisaController.text,
      offset: _carregados.length,
      limite: _kLoteRepoVazio,
      somenteAtivos: !_somenteInativos,
      somenteInativos: _somenteInativos,
    );

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
  }

  Future<void> _executarBuscaTexto() async {
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

    final lista = widget.produtoRepository.pesquisarPaginaCadastro(
      _pesquisaController.text,
      limite: _kLimiteBuscaTexto,
      somenteAtivos: !_somenteInativos,
      somenteInativos: _somenteInativos,
    );

    if (!mounted) return;
    setState(() {
      _carregados = lista;
      _exibidos = math.min(_kLoteInicialExibicao, lista.length);
      _indiceSelecionado.value = lista.isEmpty ? -1 : 0;
      _carregando = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
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

  @override
  Widget build(BuildContext context) {
    final alturaLista = adaptiveDialogListMaxHeight(context);
    final itemCount = math.min(_exibidos, _carregados.length);

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
        title: const Text('Pesquisar produto'),
        content: AdaptiveDialogPane(
          desktopWidth: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    height: 28,
                    width: 28,
                    child: Checkbox(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      value: _somenteInativos,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _somenteInativos = v);
                        _debounce?.cancel();
                        unawaited(_executarBuscaTexto());
                      },
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'Somente inativos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Spacer(),
                  if (_visiveis.isNotEmpty) ...[
                    SizedBox(
                      height: 28,
                      width: 28,
                      child: Checkbox(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        tristate: true,
                        value: _todosVisiveisMarcados
                            ? true
                            : (_algunsVisiveisMarcados ? null : false),
                        onChanged: (_) => _alternarMarcarTodosVisiveis(),
                      ),
                    ),
                    Text(
                      'Marcar exibidos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pesquisaController,
                focusNode: _pesquisaFocusNode,
                autofocus: true,
                decoration: produtoBuscaInputDecoration(
                  helperText: _helperBusca(),
                ),
                onChanged: (_) => _agendarBusca(),
                onSubmitted: (_) => _confirmarSelecionado(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: alturaLista,
                child: itemCount == 0
                    ? Center(child: Text(_rodapeLista()))
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: itemCount + (_carregando ? 1 : 0),
                          itemExtent: _kAlturaLinha,
                          addRepaintBoundaries: true,
                          cacheExtent: 280,
                          itemBuilder: (context, index) {
                            if (index >= itemCount) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                              imagesDirectoryPath:
                                  widget.produtoRepository.productImagesDirPath,
                              onToggleMarca: () => _alternarMarca(produto.id),
                              onTap: () => _fechar(produto),
                              onHover: () => _definirIndiceSelecionado(index),
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                _idsMarcados.isEmpty
                    ? _rodapeLista()
                    : '${_rodapeLista()} · ${_idsMarcados.length} marcado(s)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
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
    final estiloTitulo = Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ) ??
        const TextStyle(fontWeight: FontWeight.w600);
    final estiloSubtitulo =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final subtitulo =
        'SKU: ${widget.produto.codigoInterno} | '
        'Un: ${rotuloUnidadeProdutoLista(widget.produto)} | '
        'Categoria: ${widget.produto.categoria.isEmpty ? '-' : widget.produto.categoria}'
        '${widget.produto.ativo ? '' : ' · Inativo'}';

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => widget.onHover(),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ),
          subtitle: _TextoComDestaque(
            texto: subtitulo,
            termo: widget.consulta,
            estilo: estiloSubtitulo,
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

/// Miniatura 40px: so arquivo local (nunca baixa na lista — evita travar o celular).
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
        modo: ProdutoFotoModo.somenteLocal,
      ),
    );
  }
}

class _TextoComDestaque extends StatelessWidget {
  const _TextoComDestaque({
    required this.texto,
    required this.termo,
    required this.estilo,
  });

  final String texto;
  final String termo;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) {
    final busca = termo.trim().toLowerCase();
    if (busca.isEmpty) {
      return Text(texto, style: estilo, maxLines: 2, overflow: TextOverflow.ellipsis);
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: estilo, children: spans),
    );
  }
}

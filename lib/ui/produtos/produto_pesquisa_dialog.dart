import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/produto_busca_util.dart';
import '../../data/produto_repository.dart';
import '../../domain/produto_unidade_exibicao.dart';
import '../../model/produto.dart';
import '../layout/app_layout.dart';
import '../widgets/produto_busca_input.dart';

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
  var _indiceSelecionado = -1;
  var _temMaisNoRepo = true;
  var _carregando = false;
  var _buscaComTexto = false;
  var _fechando = false;

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
    _indiceSelecionado = -1;
    _temMaisNoRepo = true;
    _buscaComTexto = false;
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
      if (_indiceSelecionado < 0 && _carregados.isNotEmpty) {
        _indiceSelecionado = 0;
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
      _indiceSelecionado = -1;
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
      _indiceSelecionado = lista.isEmpty ? -1 : 0;
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
    if (_indiceSelecionado < 0) return;
    if (_indiceSelecionado >= _exibidos && _indiceSelecionado < _carregados.length) {
      setState(() {
        _exibidos = math.min(
          _indiceSelecionado + 1,
          _carregados.length,
        );
      });
    }
    if (!_scrollController.hasClients) return;
    final alvo = (_indiceSelecionado * _kAlturaLinha).clamp(
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
    final indice = _indiceSelecionado >= 0 ? _indiceSelecionado : 0;
    _fechar(_carregados[indice]);
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
          setState(() {
            _indiceSelecionado = math.min(
              _indiceSelecionado + 1,
              _carregados.length - 1,
            );
          });
          _garantirIndiceVisivel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() {
            _indiceSelecionado = math.max(_indiceSelecionado - 1, 0);
          });
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
                              selecionado: index == _indiceSelecionado,
                              onTap: () => _fechar(produto),
                              onHover: () {
                                if (_indiceSelecionado == index) return;
                                setState(() => _indiceSelecionado = index);
                              },
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                _rodapeLista(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _fechar,
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _ProdutoPesquisaLinha extends StatelessWidget {
  const _ProdutoPesquisaLinha({
    required this.produto,
    required this.consulta,
    required this.selecionado,
    required this.onTap,
    required this.onHover,
  });

  final Produto produto;
  final String consulta;
  final bool selecionado;
  final VoidCallback onTap;
  final VoidCallback onHover;

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
        'SKU: ${produto.codigoInterno} | '
        'Un: ${rotuloUnidadeProdutoLista(produto)} | '
        'Categoria: ${produto.categoria.isEmpty ? '-' : produto.categoria}'
        '${produto.ativo ? '' : ' · Inativo'}';

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          selected: selecionado,
          selectedTileColor: scheme.primary.withValues(alpha: 0.08),
          leading: _ProdutoFotoMiniatura(fotoPath: produto.fotoPath),
          title: _TextoComDestaque(
            texto: produto.nome,
            termo: consulta,
            estilo: estiloTitulo,
          ),
          subtitle: _TextoComDestaque(
            texto: subtitulo,
            termo: consulta,
            estilo: estiloSubtitulo,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Miniatura 40px: decode so no tamanho da tela (nao carrega o JPEG inteiro).
class _ProdutoFotoMiniatura extends StatelessWidget {
  const _ProdutoFotoMiniatura({required this.fotoPath});

  final String fotoPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = fotoPath.trim();
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.image_outlined,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );

    if (path.isEmpty) {
      return SizedBox(
        width: _kMiniaturaPx,
        height: _kMiniaturaPx,
        child: placeholder,
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (_kMiniaturaPx * dpr).round().clamp(40, 96);

    return SizedBox(
      width: _kMiniaturaPx,
      height: _kMiniaturaPx,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          key: ValueKey(path),
          width: _kMiniaturaPx,
          height: _kMiniaturaPx,
          fit: BoxFit.cover,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => placeholder,
        ),
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

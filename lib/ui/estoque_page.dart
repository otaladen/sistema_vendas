import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/app_config_repository.dart';
import '../data/reajuste_preco_repository.dart';
import '../data/sync/estoque_local_refresh_hub.dart';
import '../data/venda_repository.dart';
import 'theme/app_semantic_helper.dart';
import '../domain/estoque/estoque_diagnostico_models.dart';
import '../domain/estoque/filtro_estoque_operacional.dart';
import '../domain/fornecedor_entrada_nfe_indice.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/produto_embalagem.dart';
import '../model/produto.dart';
import '../model/usuario_sistema.dart';
import '../services/compras_preditivas_service.dart';
import '../services/estoque_diagnostico_service.dart';
import '../services/estoque_diagnostico_startup.dart';
import '../services/pdf_tabela_produtos_texto.dart';
import 'reajuste_preco_autorizacao.dart';
import 'reajuste_preco_historico_page.dart';
import 'reajuste_preco_lote_page.dart';
import 'estoque/ajuste_estoque_dialog.dart';
import 'estoque/inventario_sessoes_page.dart';
import 'estoque/estoque_alerta_strip.dart';
import 'estoque/estoque_diagnostico_sheet.dart';
import 'estoque/estoque_card_linha.dart';
import 'estoque/estoque_layout.dart';
import 'estoque/estoque_stat_tile.dart';
import 'estoque/estoque_lista_metricas.dart';
import 'estoque/estoque_tabela_cabecalho.dart';
import 'estoque/estoque_tabela_colunas.dart';
import 'estoque/estoque_tabela_linha.dart';
import 'estoque/estoque_validade_panel.dart';
import 'estoque/extrato_movimento_estoque_panel.dart';
import '../data/lote_produto_repository.dart';
import 'lista_compra_page.dart';
import 'sugestao_compra_page.dart';
import '../data/sugestao_compra_repository.dart';
import '../data/inventario_repository.dart';
import '../data/inventario_gateway.dart';
import '../data/lista_compra_repository.dart';
import '../data/api/lista_compra_api_repository.dart';
import '../data/api/inventario_api_repository.dart';
import '../data/api/reajuste_preco_api_repository.dart';
import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/api/produto_api_repository.dart';
import '../data/ponto_pedido_api_dto.dart';
import 'shell/app_shell_aba_visibilidade.dart';
import 'shell/main_menu_deps.dart';
import 'widgets/anotar_lista_compra_dialog.dart';
import 'widgets/lan_api_feedback.dart';
import 'widgets/produto_busca_input.dart';

final NumberFormat _moedaBRL = NumberFormat('#,##0.00', 'pt_BR');
const int _estoqueLoteScroll = 80;
const double _estoqueScrollAntecipacaoPx = 360;

class _ComprasPreditivasTerminalStub {
  Map<int, int> montarConsumoPorProdutoNoPeriodo({int dias = 60}) => const {};
  Map<int, bool> mapaProdutosAtivosCriticos({
    Map<int, int>? consumoPrecalculado,
  }) => const {};
  double calcularPontoPedidoExibicao(Produto produto) =>
      ComprasPreditivasService.pontoPedidoExibicaoDeCadastro(produto);
}

class EstoquePage extends StatefulWidget {
  const EstoquePage({
    super.key,
    required this.produtoRepository,
    required this.usuarioLogado,
    this.lanApiClient,
    this.listaCompraRepository,
  });

  final dynamic produtoRepository;
  final UsuarioSistema usuarioLogado;
  final dynamic lanApiClient;
  final dynamic listaCompraRepository;

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage>
    with SingleTickerProviderStateMixin {
  late dynamic _usuarioRepository;
  final _appConfigRepository = AppConfigRepository();
  late final TabController _abasController;
  int _lotesCriticosOuVencidos = 0;
  bool get _temObjectBox => widget.produtoRepository is! ProdutoApiRepository;
  LanApiClient? get _lanClient =>
      widget.lanApiClient is LanApiClient
          ? widget.lanApiClient as LanApiClient
          : MainMenuDeps.maybeOf(context)?.lanApiClient;
  bool get _temLanApi => _lanClient != null;
  late final dynamic _vendaRepository = _temObjectBox
      ? VendaRepository(widget.produtoRepository.objectBox)
      : null;
  late final dynamic _diagnosticoService = _temObjectBox
      ? EstoqueDiagnosticoService(widget.produtoRepository.objectBox)
      : null;

  bool _permitirVendaSemEstoque = true;
  EstoqueDiagnosticoResultado? _diagnosticoResultado;

  dynamic get _reajusteRepo {
    if (!_temObjectBox && _temLanApi) {
      return ReajustePrecoApiRepository(_lanClient!, widget.produtoRepository);
    }
    if (_temObjectBox) {
      return ReajustePrecoRepository(
        widget.produtoRepository.objectBox,
        widget.produtoRepository,
      );
    }
    return null;
  }

  final TextEditingController _buscaController = TextEditingController();
  Timer? _debounceBusca;
  String _filtroBusca = '';
  FiltroEstoqueOperacional _filtroOperacional = FiltroEstoqueOperacional.todos;
  String? _filtroCategoria;
  String? _filtroFornecedor;
  List<Produto> _produtos = [];
  List<Produto> _produtosFiltrados = [];
  List<String> _categoriasDisponiveis = [];
  List<String> _fornecedoresDisponiveis = [];
  FornecedorEntradaNfeIndice _indiceFornecedoresNfe =
      FornecedorEntradaNfeIndice.vazio();
  Map<int, bool> _criticoPpPorProdutoId = {};
  Map<int, int> _consumo60dPorProdutoId = {};
  Map<int, double> _ppExibicaoPorProdutoId = {};
  int _qtdCriticosPp = 0;
  int _produtosAtivosCount = 0;
  int _totalAbaixoMinimo = 0;
  double _valorEstoqueTotalCache = 0;
  int _totalReservadoCache = 0;
  int _limiteExibicaoLista = _estoqueLoteScroll;
  bool _carregandoMaisItens = false;
  bool _carregandoProdutos = false;
  bool _alertaStripOculto = false;
  bool _filtrosExpandidos = false;
  EstoqueColunaOrdenacao _colunaOrdenacao = EstoqueColunaOrdenacao.nenhuma;
  bool _ordenacaoAscendente = true;
  final ScrollController _listaVerticalScrollController = ScrollController();
  final ScrollController _listaHorizontalScrollController = ScrollController();

  bool get _temFiltrosAvancadosAtivos =>
      _filtroOperacional != FiltroEstoqueOperacional.todos ||
      _filtroCategoria != null ||
      _filtroFornecedor != null;

  dynamic get _comprasSvc => _temObjectBox
      ? ComprasPreditivasService(widget.produtoRepository.objectBox)
      : _ComprasPreditivasTerminalStub();

  @override
  void initState() {
    super.initState();
    _abasController = TabController(length: 2, vsync: this);
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    _listaVerticalScrollController.addListener(_onScrollListaVertical);
    _recarregarProdutos();
    _carregarDiagnosticoInicial();
    unawaited(_atualizarContagemLotes());
    LanApiEventHub.instance.addListener(_onLanApiEstoqueChanged);
    EstoqueLocalRefreshHub.instance.addListener(_onEstoqueLocalRefresh);
  }

  bool? _abaEstoqueAtivaAnterior;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ativa = AppShellAbaVisibilidade.estaAtiva(context);
    if (_abaEstoqueAtivaAnterior == false && ativa) {
      unawaited(_sincronizarCatalogoAoFocarAbaEstoque());
    }
    _abaEstoqueAtivaAnterior = ativa;
  }

  Future<void> _sincronizarCatalogoAoFocarAbaEstoque() async {
    final repo = widget.produtoRepository;
    if (repo is! ProdutoApiRepository) return;
    try {
      final mudou = await repo.sincronizarSeDesatualizado();
      if (mudou && mounted) await _recarregarProdutos();
    } catch (_) {}
  }

  Future<void> _atualizarContagemLotes() async {
    try {
      if (_temObjectBox) {
        final c = LoteProdutoRepository(widget.produtoRepository.objectBox)
            .contarSemaforo();
        if (!mounted) return;
        setState(() => _lotesCriticosOuVencidos = c.criticosOuVencidos);
        return;
      }
      final client = _lanClient;
      if (client == null) return;
      final m = await client.contarLotesValidade();
      if (!mounted) return;
      setState(() {
        _lotesCriticosOuVencidos =
            (m['criticosOuVencidos'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  void _onLanApiEstoqueChanged() {
    if (!mounted) return;
    if (LanApiEventHub.instance.ultimaEntidade != 'produto') return;
    unawaited(
      _refreshAposEventoProduto(LanApiEventHub.instance.ultimaEntidadeIds),
    );
  }

  void _onEstoqueLocalRefresh() {
    if (!mounted) return;
    try {
      widget.produtoRepository.atualizarCacheAposMovimentoEstoque();
    } catch (_) {}
    unawaited(_recarregarProdutos());
    if (_temObjectBox) {
      _atualizarDiagnostico();
    } else {
      unawaited(_buscarDiagnosticoRemoto(silencioso: true));
    }
  }

  Future<void> _refreshAposEventoProduto(List<int> ids) async {
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository && ids.isNotEmpty) {
      try {
        await repo.atualizarEstoquePorIds(ids);
        if (!mounted) return;
        final produtos = repo.listarTodos();
        _atualizarResumosProdutos(produtos);
        setState(() {
          _produtos = produtos;
          _atualizarListaFiltrada(resetarScroll: false);
        });
        unawaited(_buscarDiagnosticoRemoto(silencioso: true));
        return;
      } catch (_) {
        // fallback full reload abaixo
      }
    }
    await _recarregarProdutos();
    if (!mounted) return;
    if (_temObjectBox) {
      _atualizarDiagnostico();
    } else {
      unawaited(_buscarDiagnosticoRemoto(silencioso: true));
    }
  }

  Future<void> _carregarConfigEstoque() async {
    final config = await _appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
  }

  void _carregarDiagnosticoInicial() {
    if (!_temObjectBox) {
      if (_temLanApi) {
        unawaited(_buscarDiagnosticoRemoto(silencioso: true));
      }
      _carregarConfigEstoque();
      return;
    }
    _diagnosticoResultado =
        EstoqueDiagnosticoStartup.ultimoResultado ??
        _diagnosticoService.executar();
    EstoqueDiagnosticoStartup.ultimoResultado = _diagnosticoResultado;
    _carregarConfigEstoque();
  }

  void _atualizarDiagnostico() {
    if (!_temObjectBox) return;
    final novo = _diagnosticoService.executar();
    EstoqueDiagnosticoStartup.ultimoResultado = novo;
    if (!mounted) return;
    setState(() => _diagnosticoResultado = novo);
  }

  Future<EstoqueDiagnosticoResultado?> _buscarDiagnosticoRemoto({
    bool silencioso = false,
  }) async {
    final client = _lanClient;
    if (client == null) return null;
    try {
      final m = await client.obterDiagnosticoEstoque();
      final resultado = EstoqueDiagnosticoResultado.fromApiMap(m);
      if (resultado != null && mounted) {
        setState(() => _diagnosticoResultado = resultado);
      }
      return resultado;
    } on LanApiException catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostico: $e')),
        );
      }
      return null;
    } catch (e) {
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnostico: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _abrirDiagnosticoEstoque() async {
    if (!_temObjectBox && !_temLanApi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem conexao com o PC servidor. Verifique a rede e tente novamente.',
          ),
        ),
      );
      return;
    }
    await mostrarEstoqueDiagnosticoSheet(
      context: context,
      diagnosticoService: _diagnosticoService,
      vendaRepository: _vendaRepository,
      usuarioLogado: widget.usuarioLogado,
      permitirVendaSemEstoque: _permitirVendaSemEstoque,
      resultadoInicial: _diagnosticoResultado,
      aoAtualizarExterno: () {
        if (_temObjectBox) {
          _atualizarDiagnostico();
        }
        unawaited(_recarregarProdutos());
      },
      buscarRemoto: _temLanApi ? () => _buscarDiagnosticoRemoto() : null,
      reprocessarBaixaRemoto: _temLanApi
          ? (vendaId) => _lanClient!.reprocessarBaixaEstoque(
                vendaId: vendaId,
                permitirVendaSemEstoque: _permitirVendaSemEstoque,
              )
          : null,
    );
    if (!mounted) return;
    if (_temObjectBox) {
      setState(() {
        _diagnosticoResultado = EstoqueDiagnosticoStartup.ultimoResultado;
      });
    }
  }

  @override
  void dispose() {
    LanApiEventHub.instance.removeListener(_onLanApiEstoqueChanged);
    EstoqueLocalRefreshHub.instance.removeListener(_onEstoqueLocalRefresh);
    _debounceBusca?.cancel();
    _abasController.dispose();
    _listaVerticalScrollController.dispose();
    _listaHorizontalScrollController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  void _rolarListaParaTopo() {
    if (!_listaVerticalScrollController.hasClients) return;
    _listaVerticalScrollController.jumpTo(0);
  }

  void _onScrollListaVertical() {
    if (!_listaVerticalScrollController.hasClients || _carregandoMaisItens) {
      return;
    }
    final total = _produtosFiltrados.length;
    if (_limiteExibicaoLista >= total) return;

    final pos = _listaVerticalScrollController.position;
    if (pos.pixels < pos.maxScrollExtent - _estoqueScrollAntecipacaoPx) {
      return;
    }

    _carregandoMaisItens = true;
    final novoLimite = math.min(
      _limiteExibicaoLista + _estoqueLoteScroll,
      total,
    );
    if (novoLimite != _limiteExibicaoLista) {
      setState(() => _limiteExibicaoLista = novoLimite);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregandoMaisItens = false;
    });
  }

  void _resetarJanelaScroll() {
    _limiteExibicaoLista = math.min(
      _estoqueLoteScroll,
      _produtosFiltrados.length,
    );
    if (_limiteExibicaoLista == 0 && _produtosFiltrados.isNotEmpty) {
      _limiteExibicaoLista = _produtosFiltrados.length;
    }
    _rolarListaParaTopo();
  }

  void _atualizarResumosProdutos(List<Produto> produtos) {
    var ativos = 0;
    var abaixoMinimo = 0;
    var reservado = 0;
    var valorEstoque = 0.0;
    final categorias = <String>{};

    for (final p in produtos) {
      if (p.ativo) {
        ativos++;
        if (EstoqueListaMetricas.abaixoDoMinimo(p)) abaixoMinimo++;
        valorEstoque += EstoqueListaMetricas.contribuicaoValorEstoque(p);
      }
      reservado += EstoqueListaMetricas.estoqueReservadoExibicaoArredondado(p);
      final categoria = p.categoria.trim();
      if (categoria.isNotEmpty) categorias.add(categoria);
    }

    _produtosAtivosCount = ativos;
    _totalAbaixoMinimo = abaixoMinimo;
    _valorEstoqueTotalCache = valorEstoque;
    _totalReservadoCache = reservado;
    _categoriasDisponiveis = categorias.toList()..sort();
    _fornecedoresDisponiveis = _indiceFornecedoresNfe.nomesOrdenados;
  }

  void _onOrdenarColuna(EstoqueColunaOrdenacao coluna) {
    setState(() {
      if (_colunaOrdenacao == coluna) {
        _ordenacaoAscendente = !_ordenacaoAscendente;
      } else {
        _colunaOrdenacao = coluna;
        _ordenacaoAscendente = coluna == EstoqueColunaOrdenacao.cobertura;
      }
      _aplicarOrdenacaoLista(_produtosFiltrados);
      _resetarJanelaScroll();
    });
  }

  int _compararProdutosOrdenacao(Produto a, Produto b) {
    int cmp;
    switch (_colunaOrdenacao) {
      case EstoqueColunaOrdenacao.nenhuma:
        return 0;
      case EstoqueColunaOrdenacao.disponivel:
        cmp = a.estoqueLivreParaVenda.compareTo(b.estoqueLivreParaVenda);
      case EstoqueColunaOrdenacao.margem:
        cmp = EstoqueListaMetricas.margemPercentual(
          a,
        ).compareTo(EstoqueListaMetricas.margemPercentual(b));
      case EstoqueColunaOrdenacao.cobertura:
        cmp = _valorOrdenacaoCobertura(
          a,
        ).compareTo(_valorOrdenacaoCobertura(b));
      case EstoqueColunaOrdenacao.media:
        cmp = a.vendaMediaDiariaExibicao.compareTo(b.vendaMediaDiariaExibicao);
      case EstoqueColunaOrdenacao.venda:
        cmp = EstoqueListaMetricas.precoVendaExibicao(
          a,
        ).compareTo(EstoqueListaMetricas.precoVendaExibicao(b));
    }
    if (cmp != 0) return cmp;
    return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
  }

  double _valorOrdenacaoCobertura(Produto produto) {
    final dias = EstoqueListaMetricas.coberturaDias(produto);
    if (dias == null) {
      return produto.estoqueLivreParaVenda > 0 ? 99999 : -1;
    }
    return dias;
  }

  void _aplicarOrdenacaoLista(List<Produto> lista) {
    if (_colunaOrdenacao == EstoqueColunaOrdenacao.nenhuma) return;
    lista.sort((a, b) {
      final cmp = _compararProdutosOrdenacao(a, b);
      return _ordenacaoAscendente ? cmp : -cmp;
    });
  }

  void _atualizarListaFiltrada({bool resetarScroll = false}) {
    _produtosFiltrados = _aplicarFiltrosLista(_produtos);
    _aplicarOrdenacaoLista(_produtosFiltrados);
    if (resetarScroll) {
      _resetarJanelaScroll();
    } else {
      _limiteExibicaoLista = math.min(
        _limiteExibicaoLista,
        _produtosFiltrados.length,
      );
      if (_limiteExibicaoLista == 0 && _produtosFiltrados.isNotEmpty) {
        _limiteExibicaoLista = math.min(
          _estoqueLoteScroll,
          _produtosFiltrados.length,
        );
      }
    }
  }

  void _onBuscaChanged(String value) {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _filtroBusca = value;
        _atualizarListaFiltrada(resetarScroll: true);
      });
    });
  }

  Future<void> _recarregarProdutos() async {
    if (!mounted) return;
    setState(() => _carregandoProdutos = true);

    try {
      // Terminal: garante catalogo completo via API (nao so o lote parcial em cache).
      final repo = widget.produtoRepository;
      if (repo is ProdutoApiRepository) {
        try {
          await repo.hidratar();
        } on LanApiException catch (e) {
          if (mounted) {
            LanApiFeedback.snackAviso(context, e, prefixo: 'Catalogo');
          }
        }
      }

      final List<Produto> produtos;
      final Map<int, int> consumo;
      final Map<int, bool> criticos;
      final Map<int, double> pps;

      if (_temObjectBox) {
        final resultado = await Future(() {
          final lista = widget.produtoRepository.listarTodos();
          final cons = _comprasSvc.montarConsumoPorProdutoNoPeriodo(dias: 60);
          final crit = _comprasSvc.mapaProdutosAtivosCriticos(
            consumoPrecalculado: cons,
          );
          return (lista, cons, crit);
        });
        produtos = resultado.$1;
        consumo = resultado.$2;
        criticos = resultado.$3;
        pps = const {};
      } else {
        produtos = widget.produtoRepository.listarTodos();
        final remoto = await _carregarPontoPedidoDaApi();
        consumo = remoto.consumo;
        criticos = remoto.criticos;
        pps = remoto.pps;
      }

      if (!mounted) return;

      FornecedorEntradaNfeIndice indiceForn = FornecedorEntradaNfeIndice.vazio();
      if (_temObjectBox) {
        try {
          indiceForn = SugestaoCompraRepository(
            widget.produtoRepository.objectBox,
          ).indiceFornecedoresNfe();
        } catch (_) {}
      } else {
        final client = _lanClient;
        if (client != null) {
          try {
            indiceForn = FornecedorEntradaNfeIndice.deApiMap(
              await client.listarFornecedoresNfeEstoque(),
            );
          } catch (_) {}
        }
      }
      _indiceFornecedoresNfe = indiceForn;
      if (_filtroFornecedor != null &&
          !_indiceFornecedoresNfe.nomesOrdenados.contains(_filtroFornecedor)) {
        _filtroFornecedor = null;
      }

      _atualizarResumosProdutos(produtos);

      setState(() {
        _produtos = produtos;
        _consumo60dPorProdutoId = consumo;
        _criticoPpPorProdutoId = criticos;
        _ppExibicaoPorProdutoId = pps;
        _qtdCriticosPp = criticos.length;
        if (_filtroOperacional == FiltroEstoqueOperacional.ppCritico &&
            _qtdCriticosPp == 0) {
          _filtroOperacional = FiltroEstoqueOperacional.todos;
        }
        _atualizarListaFiltrada(resetarScroll: true);
        _carregandoProdutos = false;
      });
      unawaited(_atualizarContagemLotes());
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoProdutos = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao carregar estoque: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<({
    Map<int, int> consumo,
    Map<int, bool> criticos,
    Map<int, double> pps,
  })> _carregarPontoPedidoDaApi() async {
    final vazio = (
      consumo: <int, int>{},
      criticos: <int, bool>{},
      pps: <int, double>{},
    );
    final client = _lanClient;
    if (client == null) return vazio;
    try {
      final raw = await client.listarPontoPedido();
      final consumo = <int, int>{};
      final criticos = <int, bool>{};
      final pps = <int, double>{};
      for (final m in raw) {
        final item = PontoPedidoApiItem.fromApiMap(m);
        if (item == null) continue;
        consumo[item.produtoId] = item.consumo60d;
        pps[item.produtoId] = item.pontoPedido;
        if (item.critico) criticos[item.produtoId] = true;
      }
      return (consumo: consumo, criticos: criticos, pps: pps);
    } on LanApiException catch (e) {
      if (mounted) {
        LanApiFeedback.snackAviso(context, e, prefixo: 'Ponto de pedido');
      }
      return vazio;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ponto de pedido: $e')),
        );
      }
      return vazio;
    }
  }

  double _ppExibicaoDe(Produto produto) {
    final cached = _ppExibicaoPorProdutoId[produto.id];
    if (cached != null) return cached;
    return _comprasSvc.calcularPontoPedidoExibicao(produto);
  }

  bool _produtoSemGiro(Produto p, int dias) {
    final consumo = _consumo60dPorProdutoId[p.id] ?? 0;
    if (consumo > 0 && dias <= 60) return false;
    final ref = p.ultimaVendaEm ?? p.criadoEm;
    return DateTime.now().difference(ref.toLocal()).inDays >= dias;
  }

  Future<void> _abrirAjusteEstoque(Produto produto) async {
    final resultado = await showAjusteEstoqueDialog(
      context: context,
      produto: produto,
    );
    if (resultado == null || !mounted) return;
    try {
      final repo = widget.produtoRepository;
      if (repo is ProdutoApiRepository) {
        await repo.ajustarEstoqueManualRemoto(
          produtoId: produto.id,
          novaQuantidadeFisica: resultado.novaQuantidadeFisica,
          motivo: resultado.motivo,
          usuarioLogin: widget.usuarioLogado.login,
          usuarioId: widget.usuarioLogado.id,
          numeroLote: resultado.numeroLote,
          dataValidade: resultado.dataValidade,
        );
        // Ajuste remoto ja mescla o item; evita hidratar catalogo inteiro.
        try {
          await repo.atualizarEstoquePorIds([produto.id]);
        } catch (_) {}
        if (!mounted) return;
        final fresco = repo.obterPorId(produto.id);
        setState(() {
          _produtos = [
            for (final p in _produtos)
              if (p.id == produto.id) (fresco ?? p) else p,
          ];
          _atualizarListaFiltrada(resetarScroll: false);
        });
      } else {
        repo.ajustarEstoqueManual(
          produtoId: produto.id,
          novaQuantidadeFisica: resultado.novaQuantidadeFisica,
          motivo: resultado.motivo,
          usuarioLogin: widget.usuarioLogado.login,
          numeroLote: resultado.numeroLote,
          dataValidade: resultado.dataValidade,
        );
        await _recarregarProdutos();
        _atualizarDiagnostico();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estoque de "${produto.nome}" ajustado para '
            '${ProdutoEmbalagem.formatarEstoque(produto, resultado.novaQuantidadeFisica, comUnidade: true)}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(context, e, prefixo: 'Erro ao ajustar estoque');
    }
  }

  Future<void> _abrirExtratoEstoque(Produto produto) {
    return showExtratoMovimentoEstoque(
      context: context,
      tituloProduto: produto.nome,
      child: ExtratoMovimentoEstoquePanel(
        produtoRepository: widget.produtoRepository,
        produtoId: produto.id,
      ),
    );
  }

  void _onAcaoProdutoTabela(String acao, Produto produto) {
    switch (acao) {
      case 'ajustar':
        _abrirAjusteEstoque(produto);
      case 'extrato':
        _abrirExtratoEstoque(produto);
      case 'comprar':
        _anotarProdutoListaCompra(produto);
    }
  }

  String _subtituloAppBar({required bool verCusto}) {
    final partes = <String>[
      '$_produtosAtivosCount SKUs',
      '$_totalAbaixoMinimo abaixo do minimo',
    ];
    if (verCusto) {
      partes.add(_formatarMoedaBRL(_valorEstoqueTotalCache));
    }
    return partes.join(' · ');
  }

  List<Widget> _acoesAppBarEstoque({required bool verCusto}) {
    final compact = EstoqueLayout.isCompact(context);
    final largo =
        !compact &&
        MediaQuery.sizeOf(context).width >=
            EstoqueLayout.breakpointDesktopLargo;
    final acoes = <Widget>[
      if (compact)
        IconButton(
          tooltip: 'Balanço / Inventário',
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: _abrirInventario,
        ),
      if (!compact) ...[
        if (largo)
          TextButton.icon(
            onPressed: _abrirListaCompra,
            icon: const Icon(Icons.playlist_add_check_outlined, size: 20),
            label: const Text('Lista de compras'),
          )
        else
          IconButton(
            tooltip: 'Lista de compras',
            icon: const Icon(Icons.playlist_add_check_outlined),
            onPressed: _abrirListaCompra,
          ),
        if (largo)
          TextButton.icon(
            onPressed: _abrirInventario,
            icon: const Icon(Icons.fact_check_outlined, size: 20),
            label: const Text('Balanço'),
          )
        else
          IconButton(
            tooltip: 'Balanço / Inventário',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _abrirInventario,
          ),
        if (largo)
          FilledButton.tonalIcon(
            onPressed: _abrirSugestaoCompra,
            icon: const Icon(Icons.shopping_cart_outlined, size: 20),
            label: const Text('Sugestao de compra'),
          )
        else
          IconButton(
            tooltip: 'Sugestao de compra',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: _abrirSugestaoCompra,
          ),
      ],
      PopupMenuButton<String>(
        tooltip: 'Mais acoes',
        icon: const Icon(Icons.more_vert),
        onSelected: (value) async {
          switch (value) {
            case 'lista_compra':
              await _abrirListaCompra();
            case 'inventario':
              await _abrirInventario();
            case 'sugestao':
              await _abrirSugestaoCompra();
            case 'diagnostico':
              await _abrirDiagnosticoEstoque();
            case 'historico':
              _abrirHistoricoReajustes();
            case 'reajuste':
              _abrirReajustePrecos(_produtosFiltrados);
            case 'export_precos':
              await _exportarTabelaProdutos(context, incluirCustos: false);
            case 'export_custo':
              await _exportarTabelaProdutos(context, incluirCustos: true);
            case 'export_precos_pdf':
              await _exportarTabelaProdutosPdf(context, incluirCustos: false);
            case 'export_custo_pdf':
              await _exportarTabelaProdutosPdf(context, incluirCustos: true);
          }
        },
        itemBuilder: (context) {
          final diag = _diagnosticoResultado;
          final badgeDiag = diag != null && diag.temProblema
              ? ' (${diag.quantidadeCriticos + diag.quantidadeAlertas})'
              : '';
          return [
            if (compact) ...[
              const PopupMenuItem<String>(
                value: 'lista_compra',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.playlist_add_check_outlined),
                  title: Text('Lista de compras'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sugestao',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.shopping_cart_outlined),
                  title: Text('Sugestao de compra'),
                ),
              ),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem<String>(
              value: 'inventario',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.fact_check_outlined),
                title: Text('Balanço / Inventário'),
              ),
            ),
            PopupMenuItem<String>(
              value: 'diagnostico',
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.health_and_safety_outlined),
                title: Text('Diagnostico de estoque$badgeDiag'),
              ),
            ),
            if (usuarioPodeReajustePrecoLote(widget.usuarioLogado)) ...[
              const PopupMenuItem<String>(
                value: 'historico',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.history),
                  title: Text('Historico de reajustes'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'reajuste',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.price_change_outlined),
                  title: Text('Reajuste de precos em lote'),
                ),
              ),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem<String>(
              value: 'export_precos',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.sell_outlined),
                title: Text('Exportar tabela de precos'),
              ),
            ),
            if (verCusto) ...[
              const PopupMenuItem<String>(
                value: 'export_custo',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.price_change_outlined),
                  title: Text('Exportar tabela de preco e custo'),
                ),
              ),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem<String>(
              value: 'export_precos_pdf',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Exportar precos (PDF)'),
              ),
            ),
            if (verCusto)
              const PopupMenuItem<String>(
                value: 'export_custo_pdf',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.request_quote_outlined),
                  title: Text('Exportar preco e custo (PDF)'),
                ),
              ),
          ];
        },
      ),
      if (!compact) const SizedBox(width: 8),
    ];
    return acoes;
  }

  Widget _painelKpisEstoque({required bool verCusto}) {
    final semantic = context.semanticColors;
    final faixa = EstoqueLayout.isKpisFaixa(context);
    final kpis = <Widget>[
      EstoqueStatTile(
        icon: Icons.inventory_2_outlined,
        titulo: 'SKUs ativos',
        valor: '$_produtosAtivosCount',
        faixaCompacta: faixa,
      ),
      EstoqueStatTile(
        icon: Icons.trending_down,
        titulo: 'Abaixo minimo',
        valor: '$_totalAbaixoMinimo',
        destaqueCor: semantic.errorFg,
        faixaCompacta: faixa,
        onTap: () => setState(() {
          _filtroOperacional = FiltroEstoqueOperacional.abaixoMinimo;
          _filtrosExpandidos = true;
          _atualizarListaFiltrada(resetarScroll: true);
        }),
      ),
      EstoqueStatTile(
        icon: Icons.shopping_bag_outlined,
        titulo: 'PP critico',
        valor: '$_qtdCriticosPp',
        destaqueCor: semantic.warningFg,
        faixaCompacta: faixa,
        onTap: _qtdCriticosPp > 0
            ? () => setState(() {
                _filtroOperacional = FiltroEstoqueOperacional.ppCritico;
                _filtrosExpandidos = true;
                _atualizarListaFiltrada(resetarScroll: true);
              })
            : null,
      ),
      if (verCusto)
        EstoqueStatTile(
          icon: Icons.payments_outlined,
          titulo: 'Valor em estoque',
          valor: _formatarMoedaBRL(_valorEstoqueTotalCache),
          faixaCompacta: faixa,
        ),
      EstoqueStatTile(
        icon: Icons.lock_outline,
        titulo: 'Total reservado',
        valor: '$_totalReservadoCache un.',
        destaqueCor: semantic.warningFg,
        faixaCompacta: faixa,
        onTap: () => setState(() {
          _filtroOperacional = FiltroEstoqueOperacional.comReserva;
          _filtrosExpandidos = true;
          _atualizarListaFiltrada(resetarScroll: true);
        }),
      ),
    ];

    if (faixa) {
      return SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kpis.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) => kpis[i],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kpis.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: kpis[i]),
        ],
      ],
    );
  }

  Future<void> _abrirSugestaoCompra() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SugestaoCompraPage(
          produtoRepository: widget.produtoRepository,
          lanApiClient: _lanClient,
        ),
      ),
    );
    if (mounted) _recarregarProdutos();
  }

  Future<void> _abrirListaCompra() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListaCompraPage(
          produtoRepository: widget.produtoRepository,
          usuarioLogado: widget.usuarioLogado,
          listaCompraRepository:
              widget.listaCompraRepository ??
              (MainMenuDeps.maybeOf(context)?.lanApiClient != null
                  ? ListaCompraApiRepository(
                      widget.lanApiClient ??
                          MainMenuDeps.maybeOf(context)!.lanApiClient!,
                      produtoRepository: widget.produtoRepository,
                    )
                  : null),
        ),
      ),
    );
    if (mounted) _recarregarProdutos();
  }

  Future<void> _abrirInventario() async {
    final client = _lanClient;
    final InventarioGateway? repo = _temObjectBox
        ? InventarioRepository(widget.produtoRepository.objectBox)
        : (client != null
            ? InventarioApiRepository(
                client,
                produtoRepository: widget.produtoRepository,
              )
            : null);
    if (repo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Balanço requer o PC servidor ou conexão com a API da loja.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InventarioSessoesPage(
          gateway: repo,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
    if (mounted) _recarregarProdutos();
  }

  Future<void> _anotarProdutoListaCompra(Produto produto) async {
    final deps = MainMenuDeps.maybeOf(context);
    final client = widget.lanApiClient ?? deps?.lanApiClient;
    final repo = widget.listaCompraRepository ??
        (_temObjectBox
            ? ListaCompraRepository(widget.produtoRepository.objectBox)
            : (client != null
                ? ListaCompraApiRepository(
                    client,
                    produtoRepository: widget.produtoRepository,
                  )
                : null));
    if (repo == null) {
      await _abrirListaCompra();
      return;
    }
    await mostrarAnotarListaCompraDialog(
      context,
      repository: repo,
      produto: produto,
      quantidadeInicial:
          EstoqueListaMetricas.quantidadeSugeridaAnotarCompra(produto),
      criadoPor: widget.usuarioLogado.login,
    );
  }

  Future<void> _abrirReajustePrecos(List<Produto> escopo) async {
    if (_reajusteRepo == null) {
      _mostrarReajusteIndisponivel();
      return;
    }
    if (!usuarioPodeReajustePrecoLote(widget.usuarioLogado)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem permissao para reajuste em lote. Ative em Cadastros > Usuarios.',
          ),
        ),
      );
      return;
    }
    if (escopo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item na lista filtrada.')),
      );
      return;
    }
    final filtros = <String>[];
    if (_filtroBusca.trim().isNotEmpty) {
      filtros.add('busca "${_filtroBusca.trim()}"');
    }
    if (_filtroOperacional != FiltroEstoqueOperacional.todos) {
      filtros.add(_filtroOperacional.rotulo);
    }
    final tituloEscopo = filtros.isEmpty
        ? 'Todos os itens visiveis na Estoque (${escopo.length}).'
        : 'Filtros: ${filtros.join(' · ')} (${escopo.length} itens).';

    final aplicou = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReajustePrecoLotePage(
          produtoRepository: widget.produtoRepository,
          reajusteRepository: _reajusteRepo,
          usuarioRepository: _usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
          escopoInicial: escopo,
          tituloEscopo: tituloEscopo,
        ),
      ),
    );
    if (aplicou == true && mounted) _recarregarProdutos();
  }

  Future<void> _abrirHistoricoReajustes() async {
    final repo = _reajusteRepo;
    if (repo == null) {
      _mostrarReajusteIndisponivel();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReajustePrecoHistoricoPage(
          reajusteRepository: repo,
          usuarioRepository: _usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
  }

  void _mostrarReajusteIndisponivel() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sem conexao com o PC servidor para reajuste em lote.',
        ),
      ),
    );
  }

  String _formatarMoedaBRL(double valor) {
    return 'R\$ ${_moedaBRL.format(valor)}';
  }

  String _csvSeguro(String valor) {
    final texto = valor.replaceAll('"', '""');
    return '"$texto"';
  }

  String _formatarNumeroCsv(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _precoAVista(Produto produto) {
    return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
  }

  Future<void> _mostrarProgressoExportacao(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Exportando arquivo, aguarde...')),
          ],
        ),
      ),
    );
  }

  Future<void> _exportarTabelaProdutos(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar a tabela',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    if (!context.mounted) return;
    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos
          ? 'tabela_preco_custo'
          : 'tabela_precos';
      final arquivo = File(
        p.join(pastaDestino, '${tipoArquivo}_$timestamp.csv'),
      );
      final linhas = <String>[];
      linhas.add(
        incluirCustos
            ? 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Custo;Custo medio;Preco venda;Preco a vista'
            : 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Preco venda;Preco a vista',
      );
      for (final produto in produtos) {
        if (incluirCustos) {
          linhas.add(
            [
              _csvSeguro(produto.codigoInterno),
              _csvSeguro(produto.nome),
              _csvSeguro(produto.unidade),
              _csvSeguro(produto.categoria),
              ProdutoEmbalagem.formatarEstoque(produto, produto.estoqueReal),
              '${produto.quantidadeMinima}',
              _formatarNumeroCsv(produto.precoCusto),
              _formatarNumeroCsv(produto.custoMedio),
              _formatarNumeroCsv(produto.precoVenda),
              _formatarNumeroCsv(_precoAVista(produto)),
            ].join(';'),
          );
        } else {
          linhas.add(
            [
              _csvSeguro(produto.codigoInterno),
              _csvSeguro(produto.nome),
              _csvSeguro(produto.unidade),
              _csvSeguro(produto.categoria),
              ProdutoEmbalagem.formatarEstoque(produto, produto.estoqueReal),
              '${produto.quantidadeMinima}',
              _formatarNumeroCsv(produto.precoVenda),
              _formatarNumeroCsv(_precoAVista(produto)),
            ].join(';'),
          );
        }
      }
      await arquivo.writeAsString('\uFEFF${linhas.join('\n')}', encoding: utf8);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('CSV exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar CSV: $e'),
        ),
      );
    }
  }

  Future<void> _exportarTabelaProdutosPdf(
    BuildContext context, {
    required bool incluirCustos,
  }) async {
    final pastaDestino = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta para exportar o PDF',
    );
    if (pastaDestino == null || pastaDestino.trim().isEmpty) {
      return;
    }

    if (!context.mounted) return;
    _mostrarProgressoExportacao(context);
    try {
      final produtos = widget.produtoRepository.listarTodos();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final tipoArquivo = incluirCustos
          ? 'tabela_preco_custo'
          : 'tabela_precos';
      final arquivo = File(
        p.join(pastaDestino, '${tipoArquivo}_$timestamp.pdf'),
      );
      final titulo = incluirCustos
          ? 'Tabela de precos e custos'
          : 'Tabela de precos';
      final bytes = await gerarPdfTabelaProdutosTexto(
        produtos: produtos,
        incluirCustos: incluirCustos,
        titulo: titulo,
        incluirColunaEstoque: false,
      );
      await arquivo.writeAsBytes(bytes);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('PDF exportado com sucesso em: ${arquivo.path}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 7),
          content: Text('Falha ao exportar PDF: $e'),
        ),
      );
    }
  }

  List<Produto> _aplicarFiltrosLista(List<Produto> produtos) {
    final termo = _filtroBusca.trim();
    final porBusca = termo.isEmpty
        ? produtos
        : widget.produtoRepository.pesquisarNaBasePadraoPdv(
            termo,
            produtos,
            limite: 500,
            somenteAtivos: false,
          );
    return porBusca.where((p) {
      if (_filtroCategoria != null && p.categoria.trim() != _filtroCategoria) {
        return false;
      }
      if (_filtroFornecedor != null) {
        if (!_indiceFornecedoresNfe.produtoDoFornecedor(
          p.id,
          _filtroFornecedor!,
        )) {
          return false;
        }
        final abaixoMin = EstoqueListaMetricas.abaixoDoMinimo(p);
        final criticoPp = _criticoPpPorProdutoId[p.id] ?? false;
        if (!abaixoMin && !criticoPp) return false;
      }
      switch (_filtroOperacional) {
        case FiltroEstoqueOperacional.todos:
          break;
        case FiltroEstoqueOperacional.abaixoMinimo:
          if (!EstoqueListaMetricas.abaixoDoMinimo(p)) return false;
        case FiltroEstoqueOperacional.ppCritico:
          if (!(_criticoPpPorProdutoId[p.id] ?? false)) return false;
        case FiltroEstoqueOperacional.comReserva:
          if (p.estoqueReservado <= 0) return false;
        case FiltroEstoqueOperacional.estoqueNegativo:
          if (p.estoqueReal >= 0 && p.estoqueLivreParaVenda >= 0) return false;
        case FiltroEstoqueOperacional.semGiro30:
        case FiltroEstoqueOperacional.semGiro60:
        case FiltroEstoqueOperacional.semGiro90:
          final dias = _filtroOperacional.diasSemGiro!;
          if (!_produtoSemGiro(p, dias)) return false;
      }
      return true;
    }).toList();
  }

  String _montarResumoCardMobile(Produto produto, {required bool verCusto}) {
    final cobertura = EstoqueListaMetricas.formatarCobertura(produto);
    if (!verCusto) return 'Cobertura $cobertura';
    return 'Cob $cobertura · Marg ${EstoqueListaMetricas.formatarMargem(produto)} · '
        'Custo ${_formatarMoedaBRL(EstoqueListaMetricas.custoExibicao(produto))}';
  }

  Widget _rodapeStatusLista({
    required int totalItens,
    required int exibidos,
    required TextStyle? estiloRodape,
    required Color corMuted,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            totalItens == 0
                ? 'Nenhum item'
                : exibidos >= totalItens
                ? 'Mostrando todos os $totalItens itens'
                : 'Mostrando $exibidos de $totalItens · role para ver mais',
            style: estiloRodape?.copyWith(color: corMuted),
          ),
        ),
        if (exibidos < totalItens && _carregandoMaisItens)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: corMuted),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final produtos = _produtos;
    final produtosFiltrados = _produtosFiltrados;
    final totalFiltrados = produtosFiltrados.length;
    final itensExibidos = math.min(_limiteExibicaoLista, totalFiltrados);
    final temMaisItens = itensExibidos < totalFiltrados;
    final verCusto = UsuarioPermissaoHelper.tem(
      widget.usuarioLogado,
      PermissaoUsuario.verCustoMargem,
    );
    final categorias = _categoriasDisponiveis;
    final fornecedores = _fornecedoresDisponiveis;
    final theme = Theme.of(context);
    final compact = EstoqueLayout.isCompact(context);
    final padH = compact ? 10.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 52 : 64,
        titleSpacing: compact ? 8 : 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Estoque',
              style: compact
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.titleLarge,
            ),
            Text(
              compact
                  ? '$_produtosAtivosCount SKUs · $_totalAbaixoMinimo min'
                  : _subtituloAppBar(verCusto: verCusto),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: compact ? 11 : null,
              ),
            ),
          ],
        ),
        actions: _acoesAppBarEstoque(verCusto: verCusto),
        bottom: TabBar(
          controller: _abasController,
          tabs: const [
            Tab(text: 'Operacional'),
            Tab(text: 'Controle de Validades'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_carregandoProdutos) const LinearProgressIndicator(minHeight: 2),
          if (!_alertaStripOculto)
            EstoqueAlertaStrip(
              criticosDiagnostico:
                  _diagnosticoResultado?.quantidadeCriticos ?? 0,
              alertasDiagnostico: _diagnosticoResultado?.quantidadeAlertas ?? 0,
              qtdCriticosPp: _qtdCriticosPp,
              lotesCriticosOuVencidos: _lotesCriticosOuVencidos,
              onVerDiagnostico: _abrirDiagnosticoEstoque,
              onFiltrarPp: _qtdCriticosPp > 0
                  ? () {
                      _abasController.index = 0;
                      setState(() {
                        _filtroOperacional = FiltroEstoqueOperacional.ppCritico;
                        _atualizarListaFiltrada(resetarScroll: true);
                      });
                    }
                  : null,
              onListaCompra: _qtdCriticosPp > 0 ? _abrirListaCompra : null,
              onVerValidades: _lotesCriticosOuVencidos > 0
                  ? () => _abasController.animateTo(1)
                  : null,
              onDismiss: () => setState(() => _alertaStripOculto = true),
            ),
          Expanded(
            child: TabBarView(
              controller: _abasController,
              children: [
                Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        padH,
                        compact ? 8 : 12,
                        padH,
                        compact ? 6 : 8,
                      ),
                      child: _painelKpisEstoque(verCusto: verCusto),
                    ),
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(padH, 0, padH, compact ? 6 : 8),
                      child: _painelFiltrosEstoque(
                        produtos: produtos,
                        produtosFiltrados: produtosFiltrados,
                        categorias: categorias,
                        fornecedores: fornecedores,
                      ),
                    ),
                    Expanded(
                      child: _conteudoListaProdutos(
                        produtosFiltrados: produtosFiltrados,
                        itensExibidos: itensExibidos,
                        temMaisItens: temMaisItens,
                        verCusto: verCusto,
                      ),
                    ),
                  ],
                ),
                EstoqueValidadePanel(
                  produtoRepository: widget.produtoRepository,
                  lanApiClient: _lanClient,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _painelFiltrosEstoque({
    required List<Produto> produtos,
    required List<Produto> produtosFiltrados,
    required List<String> categorias,
    required List<String> fornecedores,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final estiloRodape = theme.textTheme.bodySmall;
    final corMuted = scheme.onSurfaceVariant;
    final compact = EstoqueLayout.isCompact(context);
    final larguraDrop = MediaQuery.sizeOf(context).width - (compact ? 44 : 64);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _buscaController,
            style: compact ? theme.textTheme.bodyMedium : null,
            decoration: produtoBuscaInputDecoration(
              isDense: compact,
              helperText: compact ? '' : null,
              suffixIcon: _filtroBusca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar pesquisa',
                      onPressed: () {
                        _debounceBusca?.cancel();
                        _buscaController.clear();
                        setState(() {
                          _filtroBusca = '';
                          _atualizarListaFiltrada(resetarScroll: true);
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: _onBuscaChanged,
          ),
          SizedBox(height: compact ? 4 : 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    setState(() => _filtrosExpandidos = !_filtrosExpandidos),
                style: TextButton.styleFrom(
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
                icon: Icon(
                  _filtrosExpandidos ? Icons.expand_less : Icons.tune,
                  size: 18,
                ),
                label: Text(_filtrosExpandidos ? 'Ocultar filtros' : 'Filtros'),
              ),
              if (!_filtrosExpandidos && _temFiltrosAvancadosAtivos)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.filter_alt,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
              const Spacer(),
              Text(
                'Itens: ${produtosFiltrados.length}/${produtos.length}',
                style: estiloRodape?.copyWith(
                  color: corMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_filtrosExpandidos) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: FiltroEstoqueOperacional.values.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f.rotulo),
                      selected: _filtroOperacional == f,
                      visualDensity: compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                      onSelected: (_) {
                        setState(() {
                          _filtroOperacional = f;
                          _atualizarListaFiltrada(resetarScroll: true);
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            if (categorias.isNotEmpty || fornecedores.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (categorias.isNotEmpty)
                    DropdownMenu<String?>(
                      width: compact ? larguraDrop : null,
                      label: const Text('Categoria'),
                      initialSelection: _filtroCategoria,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(
                          value: null,
                          label: 'Todas',
                        ),
                        for (final c in categorias)
                          DropdownMenuEntry<String?>(value: c, label: c),
                      ],
                      onSelected: (v) => setState(() {
                        _filtroCategoria = v;
                        _atualizarListaFiltrada(resetarScroll: true);
                      }),
                    ),
                  if (fornecedores.isNotEmpty)
                    DropdownMenu<String?>(
                      key: ValueKey(
                        'est_forn_${fornecedores.length}_${_filtroFornecedor ?? ''}',
                      ),
                      width: compact ? larguraDrop : null,
                      label: const Text('Fornecedor'),
                      initialSelection: _filtroFornecedor,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(
                          value: null,
                          label: 'Todos',
                        ),
                        for (final f in fornecedores)
                          DropdownMenuEntry<String?>(value: f, label: f),
                      ],
                      onSelected: (v) => setState(() {
                        _filtroFornecedor = v;
                        _atualizarListaFiltrada(resetarScroll: true);
                      }),
                    ),
                ],
              ),
            ],
            if (_filtroFornecedor != null) ...[
              const SizedBox(height: 6),
              Text(
                'Mostrando so SKUs com NF-e/compra desse fornecedor abaixo do ponto de pedido ou do estoque minimo.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (_temFiltrosAvancadosAtivos) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroOperacional = FiltroEstoqueOperacional.todos;
                    _filtroCategoria = null;
                    _filtroFornecedor = null;
                    _atualizarListaFiltrada(resetarScroll: true);
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 18),
                  label: const Text('Limpar filtros'),
                ),
              ),
            ],
          ],
          if (!compact) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            _rodapeStatusLista(
              totalItens: produtosFiltrados.length,
              exibidos: math.min(
                _limiteExibicaoLista,
                produtosFiltrados.length,
              ),
              estiloRodape: estiloRodape,
              corMuted: corMuted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _conteudoListaProdutos({
    required List<Produto> produtosFiltrados,
    required int itensExibidos,
    required bool temMaisItens,
    required bool verCusto,
  }) {
    if (itensExibidos == 0) {
      return Center(
        child: Text(
          produtosFiltrados.isEmpty && _produtos.isNotEmpty
              ? 'Nenhum produto corresponde aos filtros.'
              : 'Nenhum produto cadastrado.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < EstoqueLayout.breakpointMobile) {
          return _listaCardsMobile(
            produtosFiltrados: produtosFiltrados,
            itensExibidos: itensExibidos,
            temMaisItens: temMaisItens,
            verCusto: verCusto,
          );
        }
        return _tabelaProdutosEstoque(
          produtosFiltrados: produtosFiltrados,
          itensExibidos: itensExibidos,
          temMaisItens: temMaisItens,
          verCusto: verCusto,
          alturaMaxima: constraints.maxHeight,
        );
      },
    );
  }

  Widget _listaCardsMobile({
    required List<Produto> produtosFiltrados,
    required int itensExibidos,
    required bool temMaisItens,
    required bool verCusto,
  }) {
    final itemCount = itensExibidos + (temMaisItens ? 1 : 0);
    return Scrollbar(
      controller: _listaVerticalScrollController,
      thumbVisibility: false,
      child: ListView.builder(
        controller: _listaVerticalScrollController,
        primary: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= itensExibidos) {
            return _rodapeCarregandoMaisLista();
          }
          final produto = produtosFiltrados[index];
          final criticoPp = _criticoPpPorProdutoId[produto.id] ?? false;
          final ppExibicao = _ppExibicaoDe(produto);
          final resumo = _montarResumoCardMobile(produto, verCusto: verCusto);
          return EstoqueCardLinha(
            produto: produto,
            indice: index,
            criticoPp: criticoPp,
            resumoLinha: resumo,
            vendaFormatada: _formatarMoedaBRL(_precoAVista(produto)),
            ppExibicao: ppExibicao,
            onAcao: _onAcaoProdutoTabela,
          );
        },
      ),
    );
  }

  Widget _rodapeCarregandoMaisLista() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          'Carregando mais produtos...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _tabelaProdutosEstoque({
    required List<Produto> produtosFiltrados,
    required int itensExibidos,
    required bool temMaisItens,
    required bool verCusto,
    required double alturaMaxima,
  }) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final larguraTabela = math.max(
      viewportWidth,
      EstoqueTabelaColunas.larguraMinima(verCusto: verCusto),
    );
    final precisaScrollHorizontal = larguraTabela > viewportWidth + 0.5;

    Widget buildListaVertical() {
      final itemCount = itensExibidos + (temMaisItens ? 1 : 0);
      return Scrollbar(
        controller: _listaVerticalScrollController,
        thumbVisibility: true,
        interactive: true,
        child: ListView.builder(
          controller: _listaVerticalScrollController,
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index >= itensExibidos) {
              return _rodapeCarregandoMaisLista();
            }
            final produto = produtosFiltrados[index];
            final criticoPp = _criticoPpPorProdutoId[produto.id] ?? false;
            return EstoqueTabelaLinha(
              produto: produto,
              indice: index,
              criticoPp: criticoPp,
              ppExibicao: _ppExibicaoDe(produto),
              verCusto: verCusto,
              vendaFormatada: _formatarMoedaBRL(
                EstoqueListaMetricas.precoVendaExibicao(produto),
              ),
              custoFormatado: _formatarMoedaBRL(
                EstoqueListaMetricas.custoExibicao(produto),
              ),
              margemFormatada: EstoqueListaMetricas.formatarMargem(produto),
              coberturaFormatada: EstoqueListaMetricas.formatarCobertura(
                produto,
              ),
              onAcao: _onAcaoProdutoTabela,
            );
          },
        ),
      );
    }

    final tabela = SizedBox(
      width: larguraTabela,
      height: alturaMaxima,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EstoqueTabelaCabecalho(
            verCusto: verCusto,
            colunaOrdenacao: _colunaOrdenacao,
            ordenacaoAscendente: _ordenacaoAscendente,
            onOrdenar: _onOrdenarColuna,
          ),
          Expanded(child: buildListaVertical()),
        ],
      ),
    );

    if (!precisaScrollHorizontal) return tabela;

    return Scrollbar(
      controller: _listaHorizontalScrollController,
      thumbVisibility: true,
      interactive: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _listaHorizontalScrollController,
        scrollDirection: Axis.horizontal,
        primary: false,
        child: tabela,
      ),
    );
  }
}

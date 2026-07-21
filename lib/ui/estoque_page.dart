import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/app_config_repository.dart';
import '../data/produto_repository.dart';
import '../data/reajuste_preco_repository.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import 'theme/app_semantic_helper.dart';
import '../domain/estoque/estoque_diagnostico_models.dart';
import '../domain/estoque/filtro_estoque_operacional.dart';
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
import 'estoque/estoque_alerta_strip.dart';
import 'estoque/estoque_diagnostico_sheet.dart';
import 'estoque/estoque_card_linha.dart';
import 'estoque/estoque_layout.dart';
import 'estoque/estoque_stat_tile.dart';
import 'estoque/estoque_lista_metricas.dart';
import 'estoque/estoque_tabela_cabecalho.dart';
import 'estoque/estoque_tabela_colunas.dart';
import 'estoque/estoque_tabela_linha.dart';
import 'estoque/extrato_movimento_estoque_panel.dart';
import 'lista_compra_page.dart';
import 'sugestao_compra_page.dart';
import '../data/lista_compra_repository.dart';
import 'widgets/anotar_lista_compra_dialog.dart';
import 'widgets/produto_busca_input.dart';

final NumberFormat _moedaBRL = NumberFormat('#,##0.00', 'pt_BR');
const int _estoqueLoteScroll = 80;
const double _estoqueScrollAntecipacaoPx = 360;

class EstoquePage extends StatefulWidget {
  const EstoquePage({
    super.key,
    required this.produtoRepository,
    required this.usuarioLogado,
  });

  final ProdutoRepository produtoRepository;
  final UsuarioSistema usuarioLogado;

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> with SafeSyncRefreshMixin {
  final _usuarioRepository = UsuarioRepository();
  final _appConfigRepository = AppConfigRepository();
  late final VendaRepository _vendaRepository = VendaRepository(
    widget.produtoRepository.objectBox,
  );
  late final EstoqueDiagnosticoService _diagnosticoService =
      EstoqueDiagnosticoService(widget.produtoRepository.objectBox);

  bool _permitirVendaSemEstoque = true;
  EstoqueDiagnosticoResultado? _diagnosticoResultado;

  ReajustePrecoRepository get _reajusteRepo => ReajustePrecoRepository(
        widget.produtoRepository.objectBox,
        widget.produtoRepository,
      );

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
  Map<int, bool> _criticoPpPorProdutoId = {};
  Map<int, int> _consumo60dPorProdutoId = {};
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

  ComprasPreditivasService get _comprasSvc =>
      ComprasPreditivasService(widget.produtoRepository.objectBox);

  @override
  void initState() {
    super.initState();
    _listaVerticalScrollController.addListener(_onScrollListaVertical);
    _recarregarProdutos();
    _carregarDiagnosticoInicial();
    initSafeSyncRefresh(
      onReload: () {
        _recarregarProdutos();
        _atualizarDiagnostico();
      },
      aoConcluir: _snackbarDadosAtualizados,
    );
  }

  Future<void> _carregarConfigEstoque() async {
    final config = await _appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
  }

  void _carregarDiagnosticoInicial() {
    _diagnosticoResultado =
        EstoqueDiagnosticoStartup.ultimoResultado ??
        _diagnosticoService.executar();
    EstoqueDiagnosticoStartup.ultimoResultado = _diagnosticoResultado;
    _carregarConfigEstoque();
  }

  void _atualizarDiagnostico() {
    final novo = _diagnosticoService.executar();
    EstoqueDiagnosticoStartup.ultimoResultado = novo;
    if (!mounted) return;
    setState(() => _diagnosticoResultado = novo);
  }

  Future<void> _abrirDiagnosticoEstoque() async {
    await mostrarEstoqueDiagnosticoSheet(
      context: context,
      diagnosticoService: _diagnosticoService,
      vendaRepository: _vendaRepository,
      usuarioLogado: widget.usuarioLogado,
      permitirVendaSemEstoque: _permitirVendaSemEstoque,
      resultadoInicial: _diagnosticoResultado,
      aoAtualizarExterno: _atualizarDiagnostico,
    );
    if (!mounted) return;
    setState(() {
      _diagnosticoResultado = EstoqueDiagnosticoStartup.ultimoResultado;
    });
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    _debounceBusca?.cancel();
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
    final fornecedores = <String>{};

    for (final p in produtos) {
      if (p.ativo) {
        ativos++;
        if (EstoqueListaMetricas.abaixoDoMinimo(p)) abaixoMinimo++;
        valorEstoque += EstoqueListaMetricas.contribuicaoValorEstoque(p);
      }
      reservado += EstoqueListaMetricas.estoqueReservadoExibicaoArredondado(p);
      final categoria = p.categoria.trim();
      if (categoria.isNotEmpty) categorias.add(categoria);
      final fornecedor = p.fornecedor.trim();
      if (fornecedor.isNotEmpty) fornecedores.add(fornecedor);
    }

    _produtosAtivosCount = ativos;
    _totalAbaixoMinimo = abaixoMinimo;
    _valorEstoqueTotalCache = valorEstoque;
    _totalReservadoCache = reservado;
    _categoriasDisponiveis = categorias.toList()..sort();
    _fornecedoresDisponiveis = fornecedores.toList()..sort();
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
        cmp = EstoqueListaMetricas.margemPercentual(a)
            .compareTo(EstoqueListaMetricas.margemPercentual(b));
      case EstoqueColunaOrdenacao.cobertura:
        cmp = _valorOrdenacaoCobertura(a).compareTo(_valorOrdenacaoCobertura(b));
      case EstoqueColunaOrdenacao.media:
        cmp = a.vendaMediaDiaria.compareTo(b.vendaMediaDiaria);
      case EstoqueColunaOrdenacao.venda:
        cmp = EstoqueListaMetricas.precoVendaExibicao(a)
            .compareTo(EstoqueListaMetricas.precoVendaExibicao(b));
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

    final resultado = await Future(() {
      final produtos = widget.produtoRepository.listarTodos();
      final consumo = _comprasSvc.montarConsumoPorProdutoNoPeriodo(dias: 60);
      final criticos = _comprasSvc.mapaProdutosAtivosCriticos(
        consumoPrecalculado: consumo,
      );
      return (produtos, consumo, criticos);
    });

    if (!mounted) return;

    final (produtos, consumo, criticos) = resultado;
    _atualizarResumosProdutos(produtos);

    setState(() {
      _produtos = produtos;
      _consumo60dPorProdutoId = consumo;
      _criticoPpPorProdutoId = criticos;
      _qtdCriticosPp = criticos.length;
      if (_filtroOperacional == FiltroEstoqueOperacional.ppCritico &&
          _qtdCriticosPp == 0) {
        _filtroOperacional = FiltroEstoqueOperacional.todos;
      }
      _atualizarListaFiltrada(resetarScroll: true);
      _carregandoProdutos = false;
    });
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
      widget.produtoRepository.ajustarEstoqueManual(
        produtoId: produto.id,
        novaQuantidadeFisica: resultado.novaQuantidadeFisica,
        motivo: resultado.motivo,
        usuarioLogin: widget.usuarioLogado.login,
      );
      _recarregarProdutos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estoque de "${produto.nome}" ajustado para '
            '${resultado.novaQuantidadeFisica}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao ajustar estoque: $e')),
      );
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
    final largo = !compact &&
        MediaQuery.sizeOf(context).width >= EstoqueLayout.breakpointDesktopLargo;
    final acoes = <Widget>[
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
        ),
      ),
    );
    if (mounted) _recarregarProdutos();
  }

  Future<void> _anotarProdutoListaCompra(Produto produto) async {
    final repo = ListaCompraRepository(widget.produtoRepository.objectBox);
    await mostrarAnotarListaCompraDialog(
      context,
      repository: repo,
      produto: produto,
      quantidadeInicial: produto.quantidadeMinima > produto.estoqueAtual
          ? (produto.quantidadeMinima - produto.estoqueAtual).clamp(1, 99999)
          : 1,
      criadoPor: widget.usuarioLogado.login,
    );
  }

  Future<void> _abrirReajustePrecos(List<Produto> escopo) async {
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

  void _abrirHistoricoReajustes() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReajustePrecoHistoricoPage(
          reajusteRepository: _reajusteRepo,
          usuarioRepository: _usuarioRepository,
          usuarioLogado: widget.usuarioLogado,
        ),
      ),
    );
  }

  void _snackbarDadosAtualizados({required bool daRede}) {
    if (!daRede || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Dados atualizados da rede'),
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
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.csv'));
      final linhas = <String>[];
      linhas.add(
        incluirCustos
            ? 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Custo;Custo medio;Preco venda;Preco a vista'
            : 'SKU;Nome;Unidade;Categoria;Estoque;Minimo;Preco venda;Preco a vista',
      );
      for (final produto in produtos) {
        if (incluirCustos) {
          linhas.add([
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
          ].join(';'));
        } else {
          linhas.add([
            _csvSeguro(produto.codigoInterno),
            _csvSeguro(produto.nome),
            _csvSeguro(produto.unidade),
            _csvSeguro(produto.categoria),
            ProdutoEmbalagem.formatarEstoque(produto, produto.estoqueReal),
            '${produto.quantidadeMinima}',
            _formatarNumeroCsv(produto.precoVenda),
            _formatarNumeroCsv(_precoAVista(produto)),
          ].join(';'));
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
      final tipoArquivo = incluirCustos ? 'tabela_preco_custo' : 'tabela_precos';
      final arquivo = File(p.join(pastaDestino, '${tipoArquivo}_$timestamp.pdf'));
      final titulo =
          incluirCustos ? 'Tabela de precos e custos' : 'Tabela de precos';
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
      if (_filtroCategoria != null &&
          p.categoria.trim() != _filtroCategoria) {
        return false;
      }
      if (_filtroFornecedor != null &&
          p.fornecedor.trim() != _filtroFornecedor) {
        return false;
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

  String _montarResumoCardMobile(
    Produto produto, {
    required bool verCusto,
  }) {
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
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: corMuted,
            ),
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
              style: compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge,
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
      ),
      body: Column(
        children: [
          if (_carregandoProdutos)
            const LinearProgressIndicator(minHeight: 2),
          if (!_alertaStripOculto)
            EstoqueAlertaStrip(
              criticosDiagnostico:
                  _diagnosticoResultado?.quantidadeCriticos ?? 0,
              alertasDiagnostico:
                  _diagnosticoResultado?.quantidadeAlertas ?? 0,
              qtdCriticosPp: _qtdCriticosPp,
              onVerDiagnostico: _abrirDiagnosticoEstoque,
              onFiltrarPp: _qtdCriticosPp > 0
                  ? () => setState(() {
                        _filtroOperacional =
                            FiltroEstoqueOperacional.ppCritico;
                        _atualizarListaFiltrada(resetarScroll: true);
                      })
                  : null,
              onListaCompra: _qtdCriticosPp > 0 ? _abrirListaCompra : null,
              onDismiss: () => setState(() => _alertaStripOculto = true),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(padH, compact ? 8 : 12, padH, compact ? 6 : 8),
            child: _painelKpisEstoque(verCusto: verCusto),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(padH, 0, padH, compact ? 6 : 8),
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
                onPressed: () => setState(
                  () => _filtrosExpandidos = !_filtrosExpandidos,
                ),
                style: TextButton.styleFrom(
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                ),
                icon: Icon(
                  _filtrosExpandidos ? Icons.expand_less : Icons.tune,
                  size: 18,
                ),
                label: Text(
                  _filtrosExpandidos ? 'Ocultar filtros' : 'Filtros',
                ),
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
                          DropdownMenuEntry<String?>(
                            value: c,
                            label: c,
                          ),
                      ],
                      onSelected: (v) => setState(() {
                        _filtroCategoria = v;
                        _atualizarListaFiltrada(resetarScroll: true);
                      }),
                    ),
                  if (fornecedores.isNotEmpty)
                    DropdownMenu<String?>(
                      width: compact ? larguraDrop : null,
                      label: const Text('Fornecedor'),
                      initialSelection: _filtroFornecedor,
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(
                          value: null,
                          label: 'Todos',
                        ),
                        for (final f in fornecedores)
                          DropdownMenuEntry<String?>(
                            value: f,
                            label: f,
                          ),
                      ],
                      onSelected: (v) => setState(() {
                        _filtroFornecedor = v;
                        _atualizarListaFiltrada(resetarScroll: true);
                      }),
                    ),
                ],
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
              exibidos: math.min(_limiteExibicaoLista, produtosFiltrados.length),
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
          final ppExibicao = _comprasSvc.calcularPontoPedidoExibicao(produto);
          final resumo = _montarResumoCardMobile(
            produto,
            verCusto: verCusto,
          );
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
              ppExibicao: _comprasSvc.calcularPontoPedidoExibicao(produto),
              verCusto: verCusto,
              vendaFormatada: _formatarMoedaBRL(
                EstoqueListaMetricas.precoVendaExibicao(produto),
              ),
              custoFormatado: _formatarMoedaBRL(
                EstoqueListaMetricas.custoExibicao(produto),
              ),
              margemFormatada: EstoqueListaMetricas.formatarMargem(produto),
              coberturaFormatada:
                  EstoqueListaMetricas.formatarCobertura(produto),
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

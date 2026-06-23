import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/entrega_venda_helper.dart';
import '../domain/quantidade_venda_util.dart';
import '../domain/troca_com_nota_pdv_intent.dart';
import '../domain/limite_credito_helper.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/plano_fiado.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/permissao_usuario.dart';
import '../model/usuario_sistema.dart';
import '../domain/produto_embalagem.dart';
import '../domain/produto_limite_desconto_pdv.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/produto_unidade_exibicao.dart';
import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/kit_orcamento_repository.dart';
import '../data/promocao_repository.dart';
import '../data/usuario_repository.dart';
import '../domain/promocao_cadastro.dart';
import '../domain/promocao_carrinho_service.dart';
import '../domain/promocao_preco_result.dart';
import '../domain/promocao_preco_service.dart';
import '../data/produto_busca_util.dart';
import '../data/produto_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/cliente_cadastro.dart';
import '../model/cliente.dart';
import '../model/config_layout_impressao.dart';
import '../model/item_venda.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/cupom_pdf_gerado.dart';
import '../services/cupom_pdf_layout.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'pdv_consulta_preview_panel.dart';
import 'pdv_consulta_produtos_page.dart';
import 'pdv_pesquisa_comando.dart';
import 'produto_detalhe_venda_page.dart';
import 'layout/app_layout.dart';
import 'promocao_margem_autorizacao.dart';
import 'pdv_desconto_autorizacao.dart';
import 'pdv_preco_unitario_autorizacao.dart';
import 'widgets/pdv_atalhos_ajuda.dart';
import 'widgets/pdv_calculadora_panel.dart';
import 'widgets/pdv_carrinho_linha_compacta.dart';
import 'widgets/pdv_tipo_entrega_item.dart';
import 'widgets/plano_fiado_pdv_panel.dart';
import 'widgets/troca_com_nota_pdv_banner.dart';

class _LinhaPagamentoMistoPdV {
  _LinhaPagamentoMistoPdV({
    required this.meio,
    required this.valorController,
    this.parcelas = 1,
  });

  String meio;
  final TextEditingController valorController;
  int parcelas;

  void dispose() => valorController.dispose();
}

class PontoDeVendaPage extends StatefulWidget {
  const PontoDeVendaPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioLogado,
    this.intentTrocaComNota,
    this.orcamentoIdInicial,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;
  /// Apos devolucao na listagem: cliente + credito sugerido no desconto (F3).
  final TrocaComNotaPdvIntent? intentTrocaComNota;
  /// Orcamento pendente a carregar automaticamente ao abrir o PDV.
  final int? orcamentoIdInicial;

  @override
  State<PontoDeVendaPage> createState() => _PontoDeVendaPageState();
}

class _PontoDeVendaPageState extends State<PontoDeVendaPage> with SafeSyncRefreshMixin {
  bool get _podeVenderFiado => UsuarioPermissaoHelper.tem(
        widget.usuarioLogado,
        PermissaoUsuario.venderFiado,
      );

  static const int _validadeOrcamentoDias = 7;
  static const int _selecaoSemClienteValor = -1;
  static const int _selecaoNovoClienteValor = -2;
  static const double _larguraPreviewCarrinhoPdv = 280;
  static const double _breakpointPreviewCarrinhoPdv = 720;

  final _pesquisaController = TextEditingController();
  final _pesquisaFocus = FocusNode(debugLabel: 'pesquisaPdV');
  final _carrinhoFocus = FocusNode(debugLabel: 'carrinhoPdV');

  /// Checkout à direita (F7 / Shift+F7).
  final _focusClientePdV = FocusNode(debugLabel: 'pdvCliente');
  final _focusVendedorPdV = FocusNode(debugLabel: 'pdvVendedor');
  final _focusPrecoListaPdV = FocusNode(debugLabel: 'pdvPrecoLista');
  final _focusEntregaPdV = FocusNode(debugLabel: 'pdvEntregaPadrao');
  final _focusPagamentoPdV = FocusNode(debugLabel: 'pdvPagamento');
  final _focusParcelasPdV = FocusNode(debugLabel: 'pdvParcelas');

  /// Botão "Editar dados da entrega" (frete/endereço estão no dialogo).
  final _focusEditarEntregaPdV = FocusNode(debugLabel: 'pdvEditarEntrega');
  final _focusSalvarOrcamentoPdV = FocusNode(debugLabel: 'pdvSalvarOrcamento');
  final _focusDescontoPdV = FocusNode(debugLabel: 'pdvDescontoCheckout');
  final _focusPagamentoMistoSwitchPdV =
      FocusNode(debugLabel: 'pdvMistoSwitchCheckout');
  final _focusCheckoutAcaoPrimaria =
      FocusNode(debugLabel: 'pdvCheckoutAcaoPrimaria');

  /// Dialogo "Dados para enviar ao caixa" aberto (atalhos F10/Esc/1-6).
  bool _checkoutDialogAberto = false;

  /// Dialogo "Orcamento salvo" (imprimir/PDF) — bloqueia F10 do PDV.
  bool _dialogoOrcamentoSalvoAberto = false;

  /// Evita envio duplo (F10 + clique) e corrida com fechamento do dialogo.
  bool _salvandoOrcamento = false;
  bool _checkoutDialogFocoInicialAplicado = false;
  StateSetter? _checkoutDialogSetState;
  BuildContext? _checkoutDialogFechamentoContext;
  ScrollController? _checkoutDialogScroll;
  int _indiceChipPagamentoFocado = 0;
  final _pdvClienteBuscaController = TextEditingController();
  List<Cliente> _pdvClientesSugeridos = [];
  int _pdvIndiceSugestaoCliente = -1;
  final GlobalKey _keySeletorClienteAppBarPdv = GlobalKey();
  OverlayEntry? _overlaySugestoesClientePdv;
  OverlayEntry? _overlayCalculadoraPdv;
  Offset _calculadoraPdvOffset = Offset.zero;
  bool _calculadoraPdvPosicionada = false;

  /// Produtos usados recentemente nesta sessao (consulta vazia).
  final List<int> _produtosRecentesPdv = [];

  Timer? _debounceLeitorBarrasPdv;
  bool _processandoLeitorBarrasPdv = false;

  /// Ancora o painel direito para saber se o foco realmente esta no checkout (hasFocus dos nos falha).
  final GlobalKey _keyPainelCheckoutPdV = GlobalKey();
  final _valorFreteController = TextEditingController();
  final _enderecoEntregaController = TextEditingController();
  final _observacaoEntregaController = TextEditingController();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  late final KitOrcamentoRepository _kitOrcamentoRepo =
      KitOrcamentoRepository(widget.produtoRepository.objectBox);
  late final PromocaoRepository _promoRepo = PromocaoRepository(
    widget.produtoRepository.objectBox,
  );
  late final PromocaoPrecoService _promoPreco = PromocaoPrecoService(_promoRepo);
  late final PromocaoCarrinhoService _promoCarrinho =
      PromocaoCarrinhoService(_promoRepo);
  final _usuarioRepository = UsuarioRepository();
  List<Vendedor> _vendedoresAtivos = [];
  final List<_OrcamentoItemDraft> _carrinho = [];

  /// Linha selecionada no carrinho (navegacao com setas).
  int? _indiceLinhaCarrinho;

  /// Tabela de preco ativa (carrinho inteiro + novos itens; F1/F3).
  String _precoListaAtivo = 'preco1';
  String _formaPagamentoSelecionada = 'dinheiro';
  int _parcelasSelecionadas = 1;
  bool _pagamentoMistoPdV = false;
  /// Painel "Mais opcoes" (vendedor, pagamento misto) no dialogo de fechamento.
  bool _checkoutMaisOpcoesExpandido = false;
  final List<_LinhaPagamentoMistoPdV> _linhasPagamentoMisto = [];
  List<PlanoFiadoParcela> _planoFiadoParcelas = [];
  static const double _valorMinimoParcelaCreditoPdV = 5.0;
  int? _clienteSelecionadoId;
  int _indiceEnderecoSelecionado = 0;
  int? _vendedorSelecionadoId;
  /// Tipo de entrega ativo (carrinho inteiro + novos itens; Ctrl+F1–F3; tecla E na linha).
  String _tipoEntregaSelecionada = EntregaVendaHelper.tipoRetirada;

  bool get _carrinhoTemItemCarreto => _carrinho.any(
        (i) =>
            EntregaVendaHelper.normalizarTipoItem(i.tipoEntregaItem) ==
            EntregaVendaHelper.tipoEntregaLoja,
      );

  String _resolverTipoEntregaVendaCarrinho() {
    return EntregaVendaHelper.resolverTipoEntregaVenda(
      _carrinho.map((e) => e.tipoEntregaItem),
    );
  }

  String get _resumoEntregaItensCarrinho {
    if (_carrinho.isEmpty) return '';
    return EntregaVendaHelper.resumoContagem(
      _carrinho.map((e) => e.tipoEntregaItem),
    );
  }

  bool get _carrinhoEntregaMista =>
      _resolverTipoEntregaVendaCarrinho() == EntregaVendaHelper.tipoMisto;

  bool get _checkoutExibeSecaoEntrega =>
      _carrinhoTemItemCarreto || _carrinhoEntregaMista;

  void _aplicarEnderecoCarretoDoClienteSeVazio() {
    if (!_carrinhoTemItemCarreto) return;
    if (_enderecoEntregaController.text.trim().isNotEmpty) return;
    final cliente = _clienteSelecionado();
    if (cliente == null) return;
    _aplicarEnderecoSelecionadoDoCliente(cliente, _indiceEnderecoSelecionado);
  }

  static const _opcoesPrecoListaPdv = <(String, String, String)>[
    ('preco1', 'A Prazo', 'F1'),
    ('preco2', 'À Vista', 'F2'),
    ('preco3', 'Atacado', 'F3'),
  ];

  static const _opcoesEntregaPadraoPdv = <(String, String, String)>[
    (EntregaVendaHelper.tipoRetirada, 'Leva agora', 'Ctrl+F1'),
    (EntregaVendaHelper.tipoRetiradaFutura, 'Retirada futura', 'Ctrl+F2'),
    (EntregaVendaHelper.tipoEntregaLoja, 'Carreto', 'Ctrl+F3'),
  ];

  Color? _corPrecoLista(BuildContext context, String precoTipo) {
    final scheme = Theme.of(context).colorScheme;
    switch (precoTipo) {
      case 'preco2':
        return scheme.tertiary;
      case 'preco3':
        return scheme.secondary;
      case 'preco1':
      default:
        return scheme.primary;
    }
  }

  void _alternarTipoEntregaLinhaCarrinho(int index) {
    if (index < 0 || index >= _carrinho.length) return;
    setState(() {
      _carrinho[index].tipoEntregaItem = EntregaVendaHelper.proximoTipoItem(
        _carrinho[index].tipoEntregaItem,
      );
    });
  }

  int? _indiceLinhaParaMesclar(
    int produtoId,
    String precoTipo,
    String tipoEntregaItem,
    bool quantidadeEmUnidadeCompra,
  ) {
    final idx = _carrinho.indexWhere(
      (e) =>
          e.produto.id == produtoId &&
          e.precoTipo == precoTipo &&
          e.tipoEntregaItem == tipoEntregaItem &&
          e.quantidadeEmUnidadeCompra == quantidadeEmUnidadeCompra,
    );
    return idx >= 0 ? idx : null;
  }

  Future<void> _dividirLinhaCarrinho(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final orig = _carrinho[index];
    if (orig.quantidade <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para dividir, o item precisa ter pelo menos 2 unidades.',
          ),
        ),
      );
      return;
    }

    final result = await showDialog<_DividirLinhaCarrinhoResult>(
      context: context,
      builder: (ctx) => _DividirLinhaCarrinhoDialog(
        nomeProduto: orig.produto.nome,
        quantidadeTotal: orig.quantidade,
        tipoAtual: orig.tipoEntregaItem,
      ),
    );
    if (result == null || !mounted) return;

    final qNova = result.quantidadeNovaLinha;
    if (qNova <= 0 || qNova >= orig.quantidade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quantidade do novo item deve ser entre 1 e o total menos 1.',
          ),
        ),
      );
      return;
    }

    setState(() {
      orig.quantidade -= qNova;
      _carrinho.insert(
        index + 1,
        _OrcamentoItemDraft(
          produto: orig.produto,
          quantidade: qNova,
          precoTipo: orig.precoTipo,
          precoUnitario: orig.precoUnitario,
          tipoEntregaItem: result.tipoEntregaItem,
          quantidadeEmUnidadeCompra: orig.quantidadeEmUnidadeCompra,
          precoUnitarioManual: orig.precoUnitarioManual,
          promocaoId: orig.promocaoId,
          promocaoNome: orig.promocaoNome,
        ),
      );
      _indiceLinhaCarrinho = index + 1;
    });
    _carrinhoFocus.requestFocus();
  }

  int _quantidadeProdutoNoCarrinho(int produtoId) {
    return _carrinho
        .where((e) => e.produto.id == produtoId)
        .fold(0, (s, e) => s + e.quantidadeEstoque);
  }

  bool _produtoExcedeEstoqueNoCarrinho(Produto produto) {
    return _quantidadeProdutoNoCarrinho(produto.id) >
        produto.estoqueLivreParaVenda;
  }
  String _prioridadeEntregaSelecionada = 'normal';
  String _janelaEntregaSelecionada = 'nao_definida';
  DateTime? _dataEntregaMarcada;
  bool _permitirVendaSemEstoque = false;
  double _maxDescontoPercentualPdv = 15;

  /// `percentual` | `valor` — desconto sempre limitado ao configurado (% sobre subtotal).
  String _tipoDescontoPdV = 'percentual';
  final _descontoPdVController = TextEditingController();
  bool _descontoAcimaTetoAutorizadoPdv = false;
  String? _descontoAutorizadoPorPdV;
  int? _orcamentoEmEdicaoId;
  int? _orcamentoEmEdicaoNumero;
  /// Ultimo orcamento enviado ao caixa (exibido no painel apos salvar).
  int? _ultimoOrcamentoSalvoNumero;
  double? _ultimoOrcamentoSalvoTotal;
  bool _mostrarAjudaAtalhos = false;
  bool _trocaComNotaBannerVisivel = true;
  bool _trocaComNotaIntentAplicado = false;
  bool _trocaComNotaDescontoAplicado = false;
  double? _trocaComNotaCreditoAplicadoReais;
  bool _orcamentoInicialAplicado = false;

  /// Agrupa varios KeyDown do F7 no mesmo ciclo (Windows); senao executa dois passos de uma vez.
  int _checkoutF7BurstId = 0;

  void _agendarCheckoutF7Microtask(bool anterior) {
    final querAnterior = anterior;
    final id = ++_checkoutF7BurstId;
    scheduleMicrotask(() {
      if (!mounted || id != _checkoutF7BurstId) return;
      if (querAnterior) {
        _focarCampoCheckoutAnterior();
      } else {
        _focarProximoCampoCheckout();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handlerTeclasHardwarePdv);
    widget.produtoRepository.addListener(_onProdutoRepositoryChanged);
    initSafeSyncRefresh(
      onReload: _recarregarDadosSync,
      bloquearAtualizacao: _bloquearSyncPdv,
      aoConcluir: _snackbarDadosAtualizados,
    );
    _carregarDadosIniciais();
    _carregarConfiguracaoVendaSemEstoque();
    _pesquisaController.addListener(_onPesquisaPdvTextoChanged);
    _focusClientePdV.addListener(_onFocoClientePdvChanged);
    _aplicarFocoInicialPdv();
  }

  /// Ao abrir o PDV: vendedor → preco → entrega → cliente → busca (Tab).
  void _aplicarFocoInicialPdv() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_vendedoresAtivos.isNotEmpty) {
        _focusVendedorPdV.requestFocus();
        return;
      }
      _focusClientePdV.requestFocus();
    });
  }

  void _onFocoClientePdvChanged() {
    if (!_focusClientePdV.hasFocus) {
      _fecharOverlaySugestoesClientePdv();
      return;
    }
    if (_pdvClientesSugeridos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _atualizarOverlaySugestoesClientePdv();
      });
    }
  }

  bool _bloquearSyncPdv() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return true;
    return _focoPrimarioDentroDoPainelCheckout();
  }

  void _onProdutoRepositoryChanged() {
    agendarRecargaSegura();
  }

  void _recarregarDadosSync() {
    if (!mounted) return;
    _carregarDadosIniciais();
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

  @override
  void didUpdateWidget(PontoDeVendaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoRepository != widget.produtoRepository) {
      oldWidget.produtoRepository.removeListener(_onProdutoRepositoryChanged);
      widget.produtoRepository.addListener(_onProdutoRepositoryChanged);
    }
  }

  Future<void> _carregarConfiguracaoVendaSemEstoque() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) {
      return;
    }
    setState(() {
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      _maxDescontoPercentualPdv = widget.usuarioLogado.tetoDescontoPercentualPdv(
        config.maxDescontoPercentualPdv,
      );
    });
    await _aplicarIntentTrocaComNotaSeNecessario();
    await _aplicarOrcamentoInicialSeNecessario();
  }

  Future<void> _aplicarOrcamentoInicialSeNecessario() async {
    final id = widget.orcamentoIdInicial;
    if (id == null || _orcamentoInicialAplicado || !mounted) return;
    _orcamentoInicialAplicado = true;

    final venda = widget.vendaRepository.obterPorId(id);
    if (venda == null ||
        venda.status != 'orcamento' ||
        venda.cancelada) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orcamento nao encontrado ou ja foi finalizado/cancelado.',
          ),
        ),
      );
      return;
    }

    final carregou = _aplicarOrcamentoParaEdicao(venda);
    if (!carregou && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel carregar o orcamento no PDV.'),
        ),
      );
    }
  }

  Future<void> _aplicarIntentTrocaComNotaSeNecessario() async {
    final intent = widget.intentTrocaComNota;
    if (intent == null || _trocaComNotaIntentAplicado || !mounted) return;

    final cliente = widget.clienteRepository.obterPorId(intent.clienteId);
    if (cliente == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cliente id ${intent.clienteId} nao encontrado. Selecione o cliente manualmente.',
          ),
        ),
      );
      setState(() => _trocaComNotaIntentAplicado = true);
      return;
    }

    await _selecionarClienteNoOrcamento(cliente.id);
    if (!mounted) return;

    final vendedorId = intent.vendedorId;
    if (vendedorId != null &&
        vendedorId > 0 &&
        _vendedoresAtivos.any((v) => v.id == vendedorId)) {
      setState(() => _vendedorSelecionadoId = vendedorId);
    }

    setState(() => _trocaComNotaIntentAplicado = true);

    if (!mounted) return;
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Troca com nota: cliente ${cliente.nomeRazao}. '
          'Credito sugerido R\$ ${moeda.format(intent.creditoDevolucaoReais)}. '
          'Inclua os produtos novos no carrinho.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    _aplicarDescontoCreditoTrocaComNotaSePossivel();
  }

  void _aplicarDescontoCreditoTrocaComNotaSePossivel() {
    final intent = widget.intentTrocaComNota;
    if (intent == null ||
        _trocaComNotaDescontoAplicado ||
        intent.creditoDevolucaoReais <= 0.004) {
      return;
    }
    if (_maxDescontoPercentualPdv <= 0) return;
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0.004) return;

    final maxReais = _valorMaximoDescontoReaisPdV();
    final aplicar = intent.creditoDevolucaoReais
        .clamp(0.0, maxReais)
        .clamp(0.0, sub);
    if (aplicar <= 0.004) return;

    setState(() {
      _tipoDescontoPdV = 'valor';
      _descontoPdVController.text =
          aplicar.toStringAsFixed(2).replaceAll('.', ',');
      _trocaComNotaDescontoAplicado = true;
      _trocaComNotaCreditoAplicadoReais = aplicar;
    });
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    widget.produtoRepository.removeListener(_onProdutoRepositoryChanged);
    HardwareKeyboard.instance.removeHandler(_handlerTeclasHardwarePdv);
    _checkoutF7BurstId = 0;
    _carrinhoFocus.dispose();
    _focusClientePdV.removeListener(_onFocoClientePdvChanged);
    _focusClientePdV.dispose();
    _focusVendedorPdV.dispose();
    _focusPrecoListaPdV.dispose();
    _focusEntregaPdV.dispose();
    _focusPagamentoPdV.dispose();
    _focusParcelasPdV.dispose();
    _focusEditarEntregaPdV.dispose();
    _focusSalvarOrcamentoPdV.dispose();
    _focusDescontoPdV.dispose();
    _focusPagamentoMistoSwitchPdV.dispose();
    _focusCheckoutAcaoPrimaria.dispose();
    _descontoPdVController.dispose();
    _pdvClienteBuscaController.dispose();
    _fecharOverlaySugestoesClientePdv();
    _fecharCalculadoraPdv();
    _debounceLeitorBarrasPdv?.cancel();
    _pesquisaController.removeListener(_onPesquisaPdvTextoChanged);
    _pesquisaFocus.dispose();
    _pesquisaController.dispose();
    _valorFreteController.dispose();
    _enderecoEntregaController.dispose();
    _observacaoEntregaController.dispose();
    _disposeLinhasPagamentoMisto();
    super.dispose();
  }

  void _disposeLinhasPagamentoMisto() {
    for (final l in _linhasPagamentoMisto) {
      l.dispose();
    }
    _linhasPagamentoMisto.clear();
  }

  void _inicializarLinhasMistoPadrao() {
    _disposeLinhasPagamentoMisto();
    _linhasPagamentoMisto.addAll([
      _LinhaPagamentoMistoPdV(
        meio: 'dinheiro',
        valorController: TextEditingController(),
      ),
      _LinhaPagamentoMistoPdV(
        meio: 'pix',
        valorController: TextEditingController(),
      ),
    ]);
  }

  double _somaDigitadaMistoPdV() {
    var s = 0.0;
    for (final l in _linhasPagamentoMisto) {
      s += _parseValorMonetario(l.valorController.text);
    }
    return s;
  }

  List<PagamentoOrcamentoLinha>? _montarLinhasMistoParaSalvar(
    double totalEsperado,
  ) {
    if (!_pagamentoMistoPdV) return null;
    final out = <PagamentoOrcamentoLinha>[];
    for (final l in _linhasPagamentoMisto) {
      final v = _parseValorMonetario(l.valorController.text);
      if (v <= 0) continue;
      final par = l.meio == 'cartao_credito' ? l.parcelas.clamp(1, 12) : 1;
      if (l.meio == 'cartao_debito' && par != 1) {
        throw StateError('Cartao de debito so a vista.');
      }
      out.add(PagamentoOrcamentoLinha(meio: l.meio, valor: v, parcelas: par));
    }
    if (out.length < 2) {
      throw StateError(
        'Pagamento misto: informe ao menos duas partes com valor.',
      );
    }
    final soma = PagamentoOrcamentoCodec.soma(out);
    if ((soma - totalEsperado).abs() > 0.02) {
      throw StateError(
        'Soma dos meios (${_formatarMoeda(soma)}) deve ser ${_formatarMoeda(totalEsperado)}.',
      );
    }
    for (final p in out) {
      if (p.meio == 'cartao_credito') {
        final vp = p.parcelas > 0 ? p.valor / p.parcelas : p.valor;
        if (vp < _valorMinimoParcelaCreditoPdV) {
          throw StateError(
            'Parcela minima no cartao de credito: ${_formatarMoeda(_valorMinimoParcelaCreditoPdV)}.',
          );
        }
      }
    }
    final qtdFiado = out.where((p) => p.meio == 'fiado').length;
    if (qtdFiado > 1) {
      throw StateError('Pagamento misto: apenas uma linha pode ser Fiado.');
    }
    return out;
  }

  void _registrarProdutoRecente(Produto produto) {
    _produtosRecentesPdv.remove(produto.id);
    _produtosRecentesPdv.insert(0, produto.id);
    if (_produtosRecentesPdv.length > 20) {
      _produtosRecentesPdv.removeRange(20, _produtosRecentesPdv.length);
    }
  }

  void _onPesquisaPdvTextoChanged() {
    if (!_pesquisaFocus.hasFocus || _processandoLeitorBarrasPdv) return;
    final texto = _pesquisaController.text;
    if (!consultaEanProvavelCompleto(texto)) return;
    _debounceLeitorBarrasPdv?.cancel();
    _debounceLeitorBarrasPdv = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      unawaited(_tentarLeitorBarrasAutomaticoPdv());
    });
  }

  Future<void> _tentarLeitorBarrasAutomaticoPdv() async {
    if (!mounted || _processandoLeitorBarrasPdv) return;
    final texto = _pesquisaController.text.trim();
    if (!consultaEanProvavelCompleto(texto)) return;
    _processandoLeitorBarrasPdv = true;
    try {
      final comando = PdvPesquisaComando.parse(texto);
      final produto = widget.produtoRepository.resolverLeitorCodigoBarras(
        comando.termoBusca,
      );
      if (produto == null) return;
      _pesquisaController.clear();
      _registrarProdutoRecente(produto);
      final qtd = comando.quantidadeDireta ?? 1;
      await _adicionarComQuantidade(
        produto,
        qtd.toDouble(),
        precoTipo: _precoListaAtivo,
      );
      _voltarFocoParaPesquisa();
    } finally {
      _processandoLeitorBarrasPdv = false;
    }
  }

  Future<void> _processarEntradaPesquisaPdv() async {
    if (!mounted) return;
    final comando = PdvPesquisaComando.parse(_pesquisaController.text);
    final termo = comando.termoBusca;
    if (termo.isNotEmpty) {
      final porBarras = widget.produtoRepository.resolverLeitorCodigoBarras(
        termo,
      );
      if (porBarras != null) {
        _pesquisaController.clear();
        _registrarProdutoRecente(porBarras);
        final qtd = comando.quantidadeDireta ?? 1;
        if (comando.adicaoDireta || comando.quantidadeDireta != null) {
          await _adicionarComQuantidade(
            porBarras,
            qtd.toDouble(),
            precoTipo: _precoListaAtivo,
          );
        } else {
          await _adicionarAoOrcamento(porBarras);
        }
        _voltarFocoParaPesquisa();
        return;
      }
    }
    await _abrirConsultaProdutos();
  }

  Future<void> _abrirConsultaProdutos() async {
    if (!mounted) return;
    final texto = _pesquisaController.text;

    final result = await Navigator.of(context).push<PdvConsultaProdutoResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => PdvConsultaProdutosPage(
          produtoRepository: widget.produtoRepository,
          vendaRepository: widget.vendaRepository,
          termoInicial: texto,
          precoListaAtivoInicial: _precoListaAtivo,
          clienteId: _clienteSelecionadoId,
          produtosRecentesIds: List<int>.from(_produtosRecentesPdv),
          formatarMoeda: _formatarMoeda,
          rotuloPreco: _rotuloPreco,
          precoUnitarioDe: _precoExibicaoConsulta,
          resolverPromocao: (p, t) =>
              _resolverPrecoProduto(p, precoTipoLista: t),
          campanhasVigentesDe: (p) => _promoPreco.listarCampanhasVigentesParaProduto(
            p,
            dataReferencia: DateTime.now(),
            segmentoCliente: _segmentoClienteAtivo,
          ),
          quantidadeNoOrcamentoDe: _quantidadeProdutoNoCarrinho,
        ),
      ),
    );

    if (!mounted) return;
    _pesquisaController.clear();
    _voltarFocoParaPesquisa();

    if (result == null) return;

    _definirTabelaPrecoPdv(result.precoListaAtivo);
    _registrarProdutoRecente(result.produto);

    if (result.adicaoDireta) {
      await _adicionarComQuantidade(
        result.produto,
        1,
        precoTipo: result.precoListaAtivo,
      );
      return;
    }
    if (result.quantidadeDireta != null) {
      await _adicionarComQuantidade(
        result.produto,
        result.quantidadeDireta!.toDouble(),
        precoTipo: result.precoListaAtivo,
      );
      return;
    }
    if (result.abrirDialogoAdicionar) {
      await _adicionarAoOrcamento(result.produto);
    }
  }

  /// Volta o foco ao campo de pesquisa para fluxo continuado sem mouse.
  void _voltarFocoParaPesquisa() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocus.requestFocus();
    });
  }

  bool _ctrlPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  bool _shiftPressionado() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  List<FocusNode> _cadeiaFocoCheckout() {
    final nodes = <FocusNode>[];
    if (_carrinho.isNotEmpty) {
      nodes.add(_carrinhoFocus);
    }
    nodes.add(_focusSalvarOrcamentoPdV);
    return nodes;
  }

  bool _focoPrimarioDentroDoPainelCheckout() {
    final checkoutCtx = _keyPainelCheckoutPdV.currentContext;
    final primaryCtx = FocusManager.instance.primaryFocus?.context;
    if (checkoutCtx == null || primaryCtx == null) return false;
    final checkoutRo = checkoutCtx.findRenderObject();
    final primaryRo = primaryCtx.findRenderObject();
    if (checkoutRo == null || primaryRo == null) return false;
    RenderObject? walk = primaryRo;
    while (walk != null) {
      if (identical(walk, checkoutRo)) return true;
      walk = walk.parent;
    }
    return false;
  }

  int _indiceFocoNaCadeiaCheckout(List<FocusNode> chain) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null) {
      final porPrimario = chain.indexWhere((n) => identical(primary, n));
      if (porPrimario >= 0) return porPrimario;
    }
    return chain.indexWhere((n) => n.hasFocus);
  }

  /// Teclas globais do PDV (F7 checkout; seta baixo na busca entra no carrinho).
  bool _handlerTeclasHardwarePdv(KeyEvent event) {
    if (!mounted) return false;

    if (_dialogoOrcamentoSalvoAberto && event is KeyDownEvent) {
      return true;
    }

    if (_overlayCalculadoraPdv != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _fecharCalculadoraPdv();
      return true;
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleCalculadoraPdv();
      return true;
    }

    // Checkout modal: rota do PDV deixa de ser "current", mas os atalhos
    // precisam funcionar (F10 enviar, F6/F3, Esc).
    if (_checkoutDialogAberto && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f10) {
        unawaited(_checkoutDialogAcaoF10Async());
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f6) {
        _toggleCheckoutMaisOpcoesDialogoAberto();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        _focarDescontoCheckoutDialogoAberto();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _checkoutDialogFecharOuRetroceder();
        return true;
      }
    }

    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    if (event is KeyDownEvent &&
        _pesquisaFocus.hasFocus &&
        event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _carrinho.isNotEmpty) {
      _entrarFocoCarrinhoPdv();
      return true;
    }

    if (!_checkoutDialogAberto && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.f2 && _shiftPressionado()) {
        _focusClientePdV.requestFocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyN &&
          HardwareKeyboard.instance.isControlPressed) {
        unawaited(_abrirCadastroRapidoClientePdv());
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f4 &&
          _shiftPressionado()) {
        unawaited(_abrirSeletorClienteNoPdv());
        return true;
      }
    }

    if (event.logicalKey != LogicalKeyboardKey.f7) return false;

    if (event is KeyRepeatEvent) {
      return true;
    }

    if (event is! KeyDownEvent) return false;

    if (_checkoutDialogAberto) return false;

    _agendarCheckoutF7Microtask(_shiftPressionado());
    return true;
  }

  void _aplicarFocoProximoCheckout() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    if (!_focoPrimarioDentroDoPainelCheckout()) {
      chain.first.requestFocus();
      return;
    }
    final idx = _indiceFocoNaCadeiaCheckout(chain);
    if (idx < 0) {
      chain.first.requestFocus();
      return;
    }
    final next = (idx + 1) % chain.length;
    chain[next].requestFocus();
  }

  void _aplicarFocoCheckoutAnterior() {
    final chain = _cadeiaFocoCheckout();
    if (chain.isEmpty) {
      return;
    }
    if (!_focoPrimarioDentroDoPainelCheckout()) {
      chain.last.requestFocus();
      return;
    }
    final idx = _indiceFocoNaCadeiaCheckout(chain);
    if (idx < 0) {
      chain.last.requestFocus();
      return;
    }
    final prev = (idx - 1 + chain.length) % chain.length;
    chain[prev].requestFocus();
  }

  void _focarProximoCampoCheckout() {
    _aplicarFocoProximoCheckout();
  }

  void _focarCampoCheckoutAnterior() {
    _aplicarFocoCheckoutAnterior();
  }

  void _focarCarrinhoAtalho() {
    _entrarFocoCarrinhoPdv(selecionarUltimaLinha: true);
  }

  void _entrarFocoCarrinhoPdv({bool selecionarUltimaLinha = false}) {
    if (_carrinho.isEmpty) return;
    setState(() {
      if (selecionarUltimaLinha) {
        _indiceLinhaCarrinho = (_indiceLinhaCarrinho ?? _carrinho.length - 1)
            .clamp(0, _carrinho.length - 1);
      } else {
        _indiceLinhaCarrinho =
            (_indiceLinhaCarrinho ?? 0).clamp(0, _carrinho.length - 1);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _carrinhoFocus.requestFocus();
    });
  }

  void _limparPesquisaAtalho() {
    _pesquisaController.clear();
    _voltarFocoParaPesquisa();
  }

  void _irParaPesquisaProdutos() {
    _voltarFocoParaPesquisa();
  }

  /// Carrinho vazio: abre consulta (F4). Com itens: foco no campo de busca do PDV.
  void _atalhoF8Pdv() {
    if (_carrinho.isEmpty) {
      unawaited(_abrirConsultaProdutos());
      return;
    }
    _irParaPesquisaProdutos();
  }

  Future<void> _adicionarComQuantidade(
    Produto produtoIn,
    double quantidadeVenda, {
    String? precoTipo,
    String? tipoEntregaItem,
    bool quantidadeEmUnidadeCompra = false,
  }) async {
    if (quantidadeVenda <= 0) return;
    final produto = _produtoAtualizadoParaPdv(produtoIn);
    final fracionada = produto.permiteQuantidadeFracionada &&
        !quantidadeEmUnidadeCompra;
    if (!fracionada && quantidadeVenda != quantidadeVenda.roundToDouble()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${produto.nome}: quantidade inteira. Para vender com decimais '
            '(ex.: 4,50), ative "Permite venda fracionada" no cadastro do produto.',
          ),
        ),
      );
      return;
    }
    final qArmazenada = QuantidadeVendaUtil.paraArmazenamento(
      quantidadeVenda,
      fracionada: fracionada,
    );
    if (qArmazenada <= 0) return;
    final precoLista = precoTipo ?? _precoListaAtivo;
    final emEmbalagem = quantidadeEmUnidadeCompra &&
        produto.pdvPodeVenderEmUnidadeCompra;
    final qEstoque = ProdutoEmbalagem.quantidadeVendaParaEstoque(
      produto: produto,
      quantidadeDigitada: QuantidadeVendaUtil.paraEstoqueInteiro(
        produto,
        qArmazenada,
      ),
      emUnidadeCompra: emEmbalagem,
    );
    if (qEstoque <= 0) return;
    final resPreco = _resolverPrecoProduto(
      produto,
      precoTipoLista: precoLista,
      quantidade: qEstoque,
    );
    if (resPreco.emPromocao) {
      if (resPreco.quantidadeMaximaPorVenda > 0 &&
          qEstoque > resPreco.quantidadeMaximaPorVenda) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite da promocao: max. ${resPreco.quantidadeMaximaPorVenda} '
              'un. por venda para ${produto.nome}.',
            ),
          ),
        );
        return;
      }
      if (resPreco.quantidadeRestanteGlobal > 0 &&
          qEstoque > resPreco.quantidadeRestanteGlobal) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Restam apenas ${resPreco.quantidadeRestanteGlobal} un. '
              'nesta campanha.',
            ),
          ),
        );
        return;
      }
      if (resPreco.margemMinimaPercentual > 0) {
        final margem = PromocaoCadastro.margemSobrePrecoVenda(
          precoCusto: produto.precoCusto,
          precoVenda: resPreco.precoFinal,
        );
        if (margem + 0.05 < resPreco.margemMinimaPercentual) {
          final ok = await solicitarAutorizacaoMargemPromocao(
            context,
            _usuarioRepository,
            margemAtual: margem,
            margemMinima: resPreco.margemMinimaPercentual,
            nomeProduto: produto.nome,
          );
          if (!ok) return;
        }
      }
    }
    final preco = resPreco.precoTipo;
    final unit = resPreco.precoFinal;
    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = fresh.estoqueLivreParaVenda;
      if (disp <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sem estoque de ${produto.nome}.')),
        );
        return;
      }
      final jaNoCarrinho = _quantidadeProdutoNoCarrinho(produto.id);
      if (jaNoCarrinho + qEstoque > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo para ${produto.nome}: $disp ${
                ProdutoEmbalagem.normalizarUnidade(fresh.unidade)
              } (ja ha $jaNoCarrinho no orcamento).',
            ),
          ),
        );
        return;
      }
    }
    final tipoNovo = EntregaVendaHelper.normalizarTipoItem(
      tipoEntregaItem ?? _tipoEntregaSelecionada,
    );
    final idxExistente = _indiceLinhaParaMesclar(
      produto.id,
      preco,
      tipoNovo,
      emEmbalagem,
    );
    setState(() {
      if (idxExistente != null) {
        _carrinho[idxExistente].quantidade += qArmazenada;
        _indiceLinhaCarrinho = idxExistente;
      } else {
        _carrinho.add(
          _OrcamentoItemDraft(
            produto: produto,
            quantidade: qArmazenada,
            precoTipo: preco,
            precoUnitario: unit,
            tipoEntregaItem: tipoNovo,
            quantidadeEmUnidadeCompra: emEmbalagem,
            promocaoId: resPreco.promocaoId,
            promocaoNome: resPreco.promocaoNome,
          ),
        );
        _indiceLinhaCarrinho = _carrinho.length - 1;
      }
      _recalcularPromocoesCarrinho();
    });
    _aplicarDescontoCreditoTrocaComNotaSePossivel();
    _registrarProdutoRecente(produto);
    _voltarFocoParaPesquisa();
  }

  Future<void> _inserirKitNoOrcamento() async {
    final kits = _kitOrcamentoRepo.listarPorNome(somenteAtivos: true);
    if (kits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum kit ativo. Cadastre em Menu > Cadastros > Kits de orcamento.',
          ),
        ),
      );
      return;
    }

    final qtdCtrl = TextEditingController(text: '1');
    KitOrcamento escolhido = kits.first;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: const Text('Inserir kit no orcamento'),
              content: AdaptiveDialogPane(
                desktopWidth: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cada produto do kit entra no carrinho com o preco ativo (${_rotuloPreco(_precoListaAtivo)}), '
                        'multiplicado pela quantidade de kits.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kit selecionado: ${escolhido.nome}',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 220,
                        child: ListView(
                          children: [
                            for (final k in kits)
                              ListTile(
                                dense: true,
                                title: Text(k.nome),
                                selected: escolhido.id == k.id,
                                onTap: () => setDlg(() => escolhido = k),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantidade de kits',
                          hintText: '1',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Inserir'),
                ),
              ],
            );
          },
        );
      },
    );

    final mult = int.tryParse(qtdCtrl.text.trim()) ?? 0;
    qtdCtrl.dispose();

    if (confirmou != true || mult <= 0) {
      if (confirmou == true && mult <= 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantidade de kits invalida.')),
        );
      }
      return;
    }

    final completo = _kitOrcamentoRepo.obterPorId(escolhido.id);
    if (completo == null || !mounted) {
      return;
    }
    final itens = completo.itens.toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));

    var ignorados = 0;
    for (final it in itens) {
      final pid = it.produto.targetId;
      final p = pid != 0 ? widget.produtoRepository.obterPorId(pid) : null;
      if (p == null || !p.ativo) {
        ignorados++;
        continue;
      }
      final q = it.quantidade * mult;
      await _adicionarComQuantidade(p, q.toDouble());
    }

    if (!mounted) return;
    if (ignorados > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$ignorados item(ns) do kit ignorados (produto inativo ou removido).',
          ),
        ),
      );
    }
  }

  void _ajustarIndiceAposRemoverCarrinho(int removido) {
    if (_carrinho.isEmpty) {
      _indiceLinhaCarrinho = null;
      return;
    }
    final sel = _indiceLinhaCarrinho;
    if (sel == null) return;
    if (removido < sel) {
      _indiceLinhaCarrinho = sel - 1;
    } else if (removido == sel) {
      _indiceLinhaCarrinho = removido.clamp(0, _carrinho.length - 1);
    }
  }

  int _passoQuantidadeCarrinho(Produto produto) {
    if (produto.permiteQuantidadeFracionada) {
      return QuantidadeVendaUtil.escalaFracionada ~/ 10;
    }
    return 1;
  }

  void _alterarQuantidadeCarrinho(int index, int deltaArmazenado) {
    if (!_permitirVendaSemEstoque && deltaArmazenado > 0) {
      final item = _carrinho[index];
      final fresh =
          widget.produtoRepository.obterPorId(item.produto.id) ?? item.produto;
      final disp = fresh.estoqueLivreParaVenda;
      final qNova = ProdutoEmbalagem.quantidadeVendaParaEstoque(
        produto: item.produto,
        quantidadeDigitada: QuantidadeVendaUtil.paraEstoqueInteiro(
          item.produto,
          item.quantidade + deltaArmazenado,
        ),
        emUnidadeCompra: item.quantidadeEmUnidadeCompra,
      );
      if (qNova > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo: $disp ${ProdutoEmbalagem.normalizarUnidade(fresh.unidade)} '
              '(no orcamento: ${item.quantidadeEstoque}).',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      final item = _carrinho[index];
      final nova = item.quantidade + deltaArmazenado;
      if (nova <= 0) {
        _carrinho.removeAt(index);
        _ajustarIndiceAposRemoverCarrinho(index);
      } else {
        item.quantidade = nova;
      }
    });
  }

  void _removerItemCarrinho(int index) {
    setState(() {
      _carrinho.removeAt(index);
      _ajustarIndiceAposRemoverCarrinho(index);
    });
  }

  /// Setas no carrinho: ↑↓ outra linha (↑ na primeira volta a busca); +/- qtd no teclado numerico.
  KeyEventResult _onKeyCarrinho(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_carrinho.isEmpty) return KeyEventResult.ignored;

    final n = _carrinho.length;
    var idx = _indiceLinhaCarrinho ?? 0;
    idx = idx.clamp(0, n - 1);
    final ctrl = _ctrlPressionado();

    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (idx <= 0) {
          _pesquisaFocus.requestFocus();
          return KeyEventResult.handled;
        }
        setState(() => _indiceLinhaCarrinho = idx - 1);
        return KeyEventResult.handled;
      }
      setState(() {
        _indiceLinhaCarrinho = (idx + 1).clamp(0, n - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _pesquisaFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _removerItemCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      _alternarTipoEntregaLinhaCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyD) {
      _dividirLinhaCarrinho(idx);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyP) {
      unawaited(_alterarPrecoLinhaCarrinhoSelecionada());
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _alterarQuantidadeCarrinho(
        idx,
        _passoQuantidadeCarrinho(_carrinho[idx].produto),
      );
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _alterarQuantidadeCarrinho(
        idx,
        -_passoQuantidadeCarrinho(_carrinho[idx].produto),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.f9) {
      unawaited(_abrirDetalhesProdutoCarrinho());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _carregarDadosIniciais() {
    setState(() {
      _vendedoresAtivos = widget.vendedorRepository.listarAtivos();
    });
  }

  static const double _larguraSeletorVendedorAppBarPdv = 148;
  static const double _larguraSeletorClienteAppBarPdv = 156;
  static const double _larguraSeletorPrecoAppBarPdv = 108;
  static const double _larguraSeletorEntregaAppBarPdv = 124;

  String _rotuloCurtoPrecoListaCabecalhoPdV(String tipo) {
    switch (tipo) {
      case 'preco2':
        return 'Dinheiro';
      case 'preco3':
        return 'Atacado';
      case 'preco1':
      default:
        return 'A prazo';
    }
  }

  Vendedor? _vendedorSelecionadoPdv() {
    final id = _vendedorSelecionadoId;
    if (id == null) return null;
    return _vendedoresAtivos.where((v) => v.id == id).firstOrNull;
  }

  String _rotuloCurtoVendedorPdV(Vendedor? vendedor) {
    if (vendedor == null) return 'Vendedor';
    final nome = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    if (nome.isEmpty) return 'Vendedor';
    const max = 14;
    if (nome.length <= max) return nome;
    return '${nome.substring(0, max - 1)}…';
  }

  Widget _buildSeletorVendedorAppBarPdv() {
    if (_vendedoresAtivos.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itens = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('Sem vendedor'),
      ),
      ..._vendedoresAtivos.map(
        (v) => DropdownMenuItem<int?>(
          value: v.id,
          child: Text(
            _rotuloCurtoVendedorPdV(v),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    final vendedorAtual = _vendedorSelecionadoPdv();
    final tooltip = vendedorAtual == null
        ? 'Vendedor da venda (opcional)'
        : _rotuloItemVendedorPdV(vendedorAtual);

    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
      width: _larguraSeletorVendedorAppBarPdv,
      height: 30,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              key: ValueKey('pdv_vnd_${_vendedorSelecionadoId ?? 'nenhum'}'),
              isDense: true,
              isExpanded: true,
              focusNode: _focusVendedorPdV,
              value: _vendedorSelecionadoId,
              icon: Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: scheme.onSurface,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              borderRadius: BorderRadius.circular(6),
              hint: Text(
                'Vendedor',
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
              items: itens,
              onChanged: (value) {
                setState(() => _vendedorSelecionadoId = value);
              },
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildSeletorPrecoListaAppBarPdv() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itens = _opcoesPrecoListaPdv
        .map(
          (opcao) => DropdownMenuItem<String>(
            value: opcao.$1,
            child: Text(
              _rotuloCurtoPrecoListaCabecalhoPdV(opcao.$1),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Tooltip(
        message:
            'Tabela de preco (carrinho e novos itens): '
            '${_rotuloCurtoPrecoListaCabecalhoPdV(_precoListaAtivo)} (F1–F3)',
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: _larguraSeletorPrecoAppBarPdv,
          height: 30,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('pdv_prc_$_precoListaAtivo'),
                  isDense: true,
                  isExpanded: true,
                  focusNode: _focusPrecoListaPdV,
                  value: _precoListaAtivo,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _corPrecoLista(context, _precoListaAtivo),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  items: itens,
                  onChanged: (value) {
                    if (value == null) return;
                    _definirTabelaPrecoPdv(value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeletorEntregaPadraoAppBarPdv() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final itens = _opcoesEntregaPadraoPdv
        .map(
          (opcao) => DropdownMenuItem<String>(
            value: opcao.$1,
            child: Text(
              opcao.$2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: Tooltip(
        message:
            'Entrega (carrinho e novos itens): '
            '${EntregaVendaHelper.rotuloTipoItem(_tipoEntregaSelecionada)} (Ctrl+F1–F3)',
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: _larguraSeletorEntregaAppBarPdv,
          height: 30,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('pdv_ent_$_tipoEntregaSelecionada'),
                  isDense: true,
                  isExpanded: true,
                  focusNode: _focusEntregaPdV,
                  value: EntregaVendaHelper.normalizarTipoItem(
                    _tipoEntregaSelecionada,
                  ),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: PdvBotaoTipoEntregaItem.corPara(
                      context,
                      _tipoEntregaSelecionada,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  items: itens,
                  onChanged: (value) {
                    if (value == null) return;
                    _definirEntregaPadraoPdv(value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _rotuloItemVendedorPdV(Vendedor v) {
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double _parseValorMonetario(String valor) {
    final normalizado = valor.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return 0;
    return double.tryParse(normalizado) ?? 0;
  }

  Cliente? _clienteSelecionado() {
    final id = _clienteSelecionadoId;
    if (id == null) return null;
    return widget.clienteRepository.obterPorId(id);
  }

  List<EnderecoCliente> _enderecosClienteSelecionado() {
    final cliente = _clienteSelecionado();
    if (cliente == null) return const [];
    return cliente.listarEnderecos();
  }

  void _aplicarEnderecoSelecionadoDoCliente(Cliente cliente, int indice) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) {
      _indiceEnderecoSelecionado = 0;
      _enderecoEntregaController.clear();
      _observacaoEntregaController.clear();
      return;
    }
    final indiceSeguro = indice.clamp(0, enderecos.length - 1);
    final endereco = enderecos[indiceSeguro];
    _indiceEnderecoSelecionado = indiceSeguro;
    _enderecoEntregaController.text = endereco.resumo();
    _observacaoEntregaController.text = endereco.referencia.trim();
  }

  String _rotuloClienteSelecionadoPdV() {
    final cliente = _clienteSelecionado();
    return cliente?.nomeRazao ?? 'Sem cliente';
  }

  String _rotuloCurtoClientePdV(Cliente? cliente) {
    if (cliente == null) return '';
    final nome = cliente.nomeRazao.trim();
    if (nome.isEmpty) return '';
    const max = 14;
    if (nome.length <= max) return nome;
    return '${nome.substring(0, max - 1)}…';
  }

  void _sincronizarTextoBuscaClientePdv() {
    final cliente = _clienteSelecionado();
    _pdvClienteBuscaController.text = _rotuloCurtoClientePdV(cliente);
    _pdvClientesSugeridos = [];
    _pdvIndiceSugestaoCliente = -1;
    _fecharOverlaySugestoesClientePdv();
  }

  static const int _pdvMaxSugestoesCliente = 8;

  List<Cliente> _pesquisarClientesPdv(String termo) {
    final t = termo.trim();
    if (t.isEmpty) return const [];
    final encontrados = widget.clienteRepository.pesquisar(t);
    return encontrados
        .where((c) => c.ativo)
        .take(_pdvMaxSugestoesCliente)
        .toList();
  }

  void _fecharOverlaySugestoesClientePdv() {
    _overlaySugestoesClientePdv?.remove();
    _overlaySugestoesClientePdv = null;
  }

  void _fecharCalculadoraPdv() {
    _overlayCalculadoraPdv?.remove();
    _overlayCalculadoraPdv = null;
    _calculadoraPdvPosicionada = false;
    _calculadoraPdvOffset = Offset.zero;
  }

  void _toggleCalculadoraPdv() {
    if (_overlayCalculadoraPdv != null) {
      _fecharCalculadoraPdv();
      return;
    }
    final overlay = Overlay.of(context);
    _overlayCalculadoraPdv = OverlayEntry(
      builder: (overlayContext) {
        final size = MediaQuery.sizeOf(overlayContext);
        const w = PdvCalculadoraPanel.largura;
        const h = PdvCalculadoraPanel.alturaEstimada;
        if (!_calculadoraPdvPosicionada) {
          _calculadoraPdvOffset = Offset(
            (size.width - w) / 2,
            (size.height - h) / 2,
          );
          _calculadoraPdvPosicionada = true;
        }
        final left = _calculadoraPdvOffset.dx.clamp(0.0, size.width - w);
        final top = _calculadoraPdvOffset.dy.clamp(0.0, size.height - h);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                child: PdvCalculadoraPanel(
                  onFechar: _fecharCalculadoraPdv,
                  onPanDelta: (delta) {
                    final area = MediaQuery.sizeOf(overlayContext);
                    _calculadoraPdvOffset = Offset(
                      (_calculadoraPdvOffset.dx + delta.dx)
                          .clamp(0.0, area.width - w),
                      (_calculadoraPdvOffset.dy + delta.dy)
                          .clamp(0.0, area.height - h),
                    );
                    _overlayCalculadoraPdv?.markNeedsBuild();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayCalculadoraPdv!);
  }

  void _atualizarOverlaySugestoesClientePdv() {
    _fecharOverlaySugestoesClientePdv();
    if (_pdvClientesSugeridos.isEmpty || !_focusClientePdV.hasFocus) return;

    final box =
        _keySeletorClienteAppBarPdv.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return;

    final offset = box.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);

    _overlaySugestoesClientePdv = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(overlayContext);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _fecharOverlaySugestoesClientePdv,
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy + box.size.height + 2,
              width: 300,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _pdvClientesSugeridos.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cliente = _pdvClientesSugeridos[index];
                      final selecionado = index == _pdvIndiceSugestaoCliente;
                      return ListTile(
                        dense: true,
                        selected: selecionado,
                        title: Text(
                          cliente.nomeRazao,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            unawaited(_aplicarClientePdv(cliente)),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlaySugestoesClientePdv!);
  }

  void _atualizarSugestoesClientePdv(String texto) {
    setState(() {
      _pdvClientesSugeridos = _pesquisarClientesPdv(texto);
      _pdvIndiceSugestaoCliente =
          _pdvClientesSugeridos.isEmpty ? -1 : 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _atualizarOverlaySugestoesClientePdv();
    });
  }

  Future<void> _aplicarClientePdv(Cliente? cliente) async {
    await _selecionarClienteNoOrcamento(cliente?.id);
    if (!mounted) return;
    setState(() => _sincronizarTextoBuscaClientePdv());
  }

  Future<void> _confirmarBuscaClientePdv() async {
    if (_pdvIndiceSugestaoCliente >= 0 &&
        _pdvIndiceSugestaoCliente < _pdvClientesSugeridos.length) {
      await _aplicarClientePdv(_pdvClientesSugeridos[_pdvIndiceSugestaoCliente]);
      return;
    }

    final termo = _pdvClienteBuscaController.text.trim();
    if (termo.isEmpty) {
      await _aplicarClientePdv(null);
      return;
    }

    final lista = _pesquisarClientesPdv(termo);
    if (lista.length == 1) {
      await _aplicarClientePdv(lista.first);
      return;
    }
    if (lista.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nenhum cliente encontrado para "$termo".')),
      );
      setState(() {
        _pdvClientesSugeridos = [];
        _pdvIndiceSugestaoCliente = -1;
      });
      _fecharOverlaySugestoesClientePdv();
      return;
    }

    setState(() {
      _pdvClientesSugeridos = lista;
      _pdvIndiceSugestaoCliente = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _atualizarOverlaySugestoesClientePdv();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Varios clientes — escolha na lista ou refine a busca.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _abrirCadastroRapidoClientePdv() async {
    final nomeController = TextEditingController();
    final telefoneController = TextEditingController();
    final nomeFocus = FocusNode();

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.pop(ctx, false);
            },
            const SingleActivator(LogicalKeyboardKey.enter): () {
              Navigator.pop(ctx, true);
            },
          },
          child: AlertDialog(
            title: const Text('Cadastro rapido de cliente'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeController,
                    focusNode: nomeFocus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                    ),
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: telefoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Telefone / WhatsApp',
                    ),
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar (Enter)'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || salvar != true) {
      nomeFocus.dispose();
      nomeController.dispose();
      telefoneController.dispose();
      return;
    }

    final nome = nomeController.text.trim();
    final telefone = telefoneController.text.replaceAll(RegExp(r'\D'), '');
    nomeFocus.dispose();
    nomeController.dispose();
    telefoneController.dispose();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do cliente.')),
      );
      return;
    }
    final agora = DateTime.now().toUtc();
    final cliente = Cliente(
      nomeRazao: nome,
      telefone: telefone,
      whatsapp: telefone,
      segmento: 'consumidor',
      origemCadastro: 'balcao',
      ativo: true,
      criadoEm: agora,
      atualizadoEm: agora,
    );
    final id = widget.clienteRepository.salvar(cliente);
    final salvo = widget.clienteRepository.obterPorId(id);
    if (salvo == null) return;

    await _aplicarClientePdv(salvo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cliente "${salvo.nomeRazao}" cadastrado.')),
    );
  }

  void _focarDescontoCheckoutDialogoAberto() {
    if (_maxDescontoPercentualPdv <= 0) return;
    _focusDescontoPdV.requestFocus();
  }

  Future<void> _selecionarClienteNoOrcamento(int? value) async {
    if (value == null) {
      setState(() {
        _clienteSelecionadoId = null;
        _indiceEnderecoSelecionado = 0;
        _atualizarEntregaCarrinhoComTipo(EntregaVendaHelper.tipoRetirada);
        _prioridadeEntregaSelecionada = 'normal';
        _janelaEntregaSelecionada = 'nao_definida';
        _dataEntregaMarcada = null;
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
        _atualizarPrecosCarrinhoComTabela(_precoListaAtivo);
      });
      return;
    }
    final cliente = widget.clienteRepository.obterPorId(value);
    if (cliente == null) return;
    final tabela = ClienteCadastro.normalizarTabelaPreco(
      cliente.tabelaPrecoPadrao,
    );
    setState(() {
      _clienteSelecionadoId = value;
      if (cliente.vendedorResponsavelId > 0) {
        _vendedorSelecionadoId = cliente.vendedorResponsavelId;
      }
      _aplicarEnderecoSelecionadoDoCliente(
        cliente,
        cliente.indiceEnderecoPadraoEntrega(),
      );
      _atualizarPrecosCarrinhoComTabela(tabela);
      _aplicarSugestaoFormaPagamentoPorTabela(tabela);
    });
    if (!cliente.ativo && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cliente "${cliente.nomeRazao}" esta inativo no cadastro.',
          ),
        ),
      );
    }
    if (cliente.bloqueadoFiado && mounted) {
      final motivo = cliente.motivoBloqueio.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            motivo.isEmpty
                ? 'Fiado bloqueado para este cliente.'
                : 'Fiado bloqueado: $motivo',
          ),
        ),
      );
    }
  }

  Future<void> _abrirCadastroNovoClienteNoPdv({
    StateSetter? setDialogState,
  }) async {
    final clienteCriado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientesPage(
          clienteRepository: widget.clienteRepository,
          vendaRepository: widget.vendaRepository,
          vendedorRepository: widget.vendedorRepository,
          retornarClienteAoSalvar: true,
        ),
      ),
    );
    if (!mounted || clienteCriado == null) {
      return;
    }
    await _selecionarClienteNoOrcamento(clienteCriado.id);
    _sincronizarTextoBuscaClientePdv();
    setDialogState?.call(() {});
  }

  KeyEventResult _onKeyClientePdv(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyN &&
        HardwareKeyboard.instance.isControlPressed) {
      unawaited(_abrirCadastroRapidoClientePdv());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f4 && _shiftPressionado()) {
      unawaited(_abrirSeletorClienteNoPdv());
      return KeyEventResult.handled;
    }

    if (_pdvClientesSugeridos.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          final max = _pdvClientesSugeridos.length - 1;
          _pdvIndiceSugestaoCliente =
              (_pdvIndiceSugestaoCliente + 1).clamp(0, max);
        });
        _atualizarOverlaySugestoesClientePdv();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          final max = _pdvClientesSugeridos.length - 1;
          _pdvIndiceSugestaoCliente = _pdvIndiceSugestaoCliente <= 0
              ? max
              : _pdvIndiceSugestaoCliente - 1;
        });
        _atualizarOverlaySugestoesClientePdv();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_confirmarBuscaClientePdv());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && _pdvClientesSugeridos.isNotEmpty) {
      setState(() {
        _pdvClientesSugeridos = [];
        _pdvIndiceSugestaoCliente = -1;
      });
      _fecharOverlaySugestoesClientePdv();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildSeletorClienteAppBarPdv() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clienteAtual = _clienteSelecionado();
    final faltaClienteFiado = _precisaPlanoFiadoPdV() &&
        (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0);
    final tooltip = clienteAtual == null
        ? 'Cliente da venda (opcional) · Shift+F2 · Shift+F4 lista · Ctrl+N novo'
        : clienteAtual.nomeRazao;

    return FocusTraversalOrder(
      order: const NumericFocusOrder(4),
      child: Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: _keySeletorClienteAppBarPdv,
            width: _larguraSeletorClienteAppBarPdv,
            height: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: faltaClienteFiado
                      ? scheme.error
                      : scheme.outlineVariant.withValues(alpha: 0.45),
                  width: faltaClienteFiado ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Focus(
                  onKeyEvent: _onKeyClientePdv,
                  child: TextField(
                    controller: _pdvClienteBuscaController,
                    focusNode: _focusClientePdV,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textCapitalization: TextCapitalization.words,
                    cursorHeight: 14,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Cliente',
                      hintStyle: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    onChanged: _atualizarSugestoesClientePdv,
                    onSubmitted: (_) => unawaited(_confirmarBuscaClientePdv()),
                    onTapOutside: (_) => _fecharOverlaySugestoesClientePdv(),
                  ),
                ),
                ),
              ),
            ),
          ),
          Focus(
            skipTraversal: true,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Lista de clientes (Shift+F4)',
              icon: const Icon(Icons.list_alt, size: 18),
              onPressed: () => unawaited(_abrirSeletorClienteNoPdv()),
            ),
          ),
          Focus(
            skipTraversal: true,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Novo cliente (Ctrl+N)',
              icon: const Icon(Icons.person_add_alt, size: 18),
              onPressed: () => unawaited(_abrirCadastroRapidoClientePdv()),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _abrirSeletorClienteNoPdv({StateSetter? setDialogState}) async {
    final pesquisaController = TextEditingController();
    final resultado = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var filtrados = widget.clienteRepository.listarPaginado(
          limit: 60,
          somenteAtivos: true,
        );
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Selecionar cliente'),
              content: AdaptiveDialogPane(
                desktopWidth: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por nome, documento, telefone...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim();
                        setDialogState(() {
                          filtrados = termo.isEmpty
                              ? widget.clienteRepository.listarPaginado(
                                  limit: 60,
                                  somenteAtivos: true,
                                )
                              : widget.clienteRepository
                                  .pesquisar(termo)
                                  .where((c) => c.ativo)
                                  .take(60)
                                  .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Sem cliente'),
                      onTap: () =>
                          Navigator.pop(dialogContext, _selecaoSemClienteValor),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_add_alt_1_outlined),
                      title: const Text('+ Novo cliente...'),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        _selecaoNovoClienteValor,
                      ),
                    ),
                    const Divider(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: adaptiveDialogListMaxHeight(
                          context,
                          desktopFactor: 0.45,
                          mobileFactor: 0.38,
                        ),
                      ),
                      child: filtrados.isEmpty
                          ? const Center(
                              child: Text('Nenhum cliente encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final c = filtrados[index];
                                final documento = c.documento.trim().isEmpty
                                    ? '-'
                                    : c.documento;
                                return ListTile(
                                  dense: true,
                                  title: Text(c.nomeRazao),
                                  subtitle: Text(
                                    'Doc: $documento | Tel: ${c.telefone.trim().isEmpty ? '-' : c.telefone}',
                                  ),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, c.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaController.dispose();

    if (!mounted || resultado == null) {
      return;
    }
    if (resultado == _selecaoNovoClienteValor) {
      await _abrirCadastroNovoClienteNoPdv(setDialogState: setDialogState);
      return;
    }
    if (resultado == _selecaoSemClienteValor) {
      await _selecionarClienteNoOrcamento(null);
      _sincronizarTextoBuscaClientePdv();
      setDialogState?.call(() {});
      if (mounted) setState(() {});
      return;
    }
    await _selecionarClienteNoOrcamento(resultado);
    _sincronizarTextoBuscaClientePdv();
    setDialogState?.call(() {});
    if (mounted) setState(() {});
  }

  String _montarEnderecoEntregaCliente(Cliente cliente) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) return '';
    return enderecos.first.resumo();
  }

  String _montarObservacaoEntregaCliente(Cliente cliente) {
    final enderecos = cliente.listarEnderecos();
    if (enderecos.isEmpty) return '';
    return enderecos.first.referencia.trim();
  }

  String _resumoEntrega() {
    final endereco = _enderecoEntregaController.text.trim();
    final obs = _observacaoEntregaController.text.trim();
    final frete = _valorFreteController.text.trim();
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(endereco);
    }
    if (obs.isNotEmpty) {
      partes.add('Obs: $obs');
    }
    if (frete.isNotEmpty && _parseValorMonetario(frete) > 0) {
      partes.add('Frete: ${_formatarMoeda(_parseValorMonetario(frete))}');
    }
    if (_dataEntregaMarcada != null) {
      partes.add(
        'Data marcada: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
      );
    }
    return partes.isEmpty
        ? 'Sem dados de entrega informados.'
        : partes.join(' | ');
  }

  Future<_EntregaDialogResult?> _abrirDialogEntregaCliente({
    required Cliente cliente,
  }) async {
    final enderecos = cliente.listarEnderecos();
    final enderecoInicial = _enderecoEntregaController.text.trim().isNotEmpty
        ? _enderecoEntregaController.text.trim()
        : _montarEnderecoEntregaCliente(cliente);
    final obsInicial = _observacaoEntregaController.text.trim().isNotEmpty
        ? _observacaoEntregaController.text.trim()
        : _montarObservacaoEntregaCliente(cliente);
    return showDialog<_EntregaDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _EntregaClienteDialog(
          clienteNome: cliente.nomeRazao,
          enderecosDisponiveis: enderecos,
          indiceEnderecoInicial: _indiceEnderecoSelecionado,
          enderecoInicial: enderecoInicial,
          observacaoInicial: obsInicial,
          valorFreteInicial: _valorFreteController.text.trim(),
        );
      },
    );
  }

  bool _estoqueCriticoPdv(Produto p) => p.estoqueReal < p.quantidadeMinima;

  _OrcamentoItemDraft? get _linhaCarrinhoSelecionada {
    final i = _indiceLinhaCarrinho;
    if (i == null || i < 0 || i >= _carrinho.length) return null;
    return _carrinho[i];
  }

  Future<void> _alterarPrecoLinhaCarrinhoSelecionada() async {
    final idx = _indiceLinhaCarrinho;
    if (idx == null || idx < 0 || idx >= _carrinho.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um item no carrinho.')),
      );
      return;
    }
    await _alterarPrecoLinhaCarrinho(idx);
  }

  Future<void> _alterarPrecoLinhaCarrinho(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final linha = _carrinho[index];
    final precoTabela = _resolverPrecoProduto(
      linha.produto,
      precoTipoLista: linha.precoTipo,
      quantidade: linha.quantidadeEstoque,
    ).precoFinal;

    final result = await solicitarAlteracaoPrecoUnitarioPdv(
      context,
      _usuarioRepository,
      usuarioLogado: widget.usuarioLogado,
      nomeProduto: linha.produto.nome,
      precoAtual: linha.precoUnitario,
      precoTabela: precoTabela,
      rotuloTabela: _rotuloPreco(linha.precoTipo),
      formatarMoeda: _formatarMoeda,
    );
    if (result == null || !mounted) return;

    setState(() {
      linha.precoUnitario = result.novoPreco;
      linha.precoUnitarioManual = result.manual;
      if (!result.manual) {
        final r = _resolverPrecoProduto(
          linha.produto,
          precoTipoLista: linha.precoTipo,
          quantidade: linha.quantidadeEstoque,
        );
        linha.precoUnitario = r.precoFinal;
        linha.promocaoId = r.promocaoId;
        linha.promocaoNome = r.promocaoNome;
      } else {
        linha.promocaoId = 0;
        linha.promocaoNome = '';
      }
    });
    _carrinhoFocus.requestFocus();
  }

  Future<void> _abrirDetalhesProdutoCarrinho() async {
    final linha = _linhaCarrinhoSelecionada;
    if (linha == null) return;
    final campanhas = _promoPreco.listarCampanhasVigentesParaProduto(
      linha.produto,
      dataReferencia: DateTime.now(),
      segmentoCliente: _segmentoClienteAtivo,
      quantidade: linha.quantidadeEstoque,
    );
    await mostrarModalDetalheProdutoVenda(
      context,
      produto: linha.produto,
      campanhasVigentes: campanhas,
    );
    if (!mounted) return;
    _carrinhoFocus.requestFocus();
  }

  Widget _buildPreviewCarrinhoPdv({required bool compacto}) {
    final linha = _linhaCarrinhoSelecionada;
    if (linha == null) return const SizedBox.shrink();
    final campanhas = _promoPreco.listarCampanhasVigentesParaProduto(
      linha.produto,
      dataReferencia: DateTime.now(),
      segmentoCliente: _segmentoClienteAtivo,
      quantidade: linha.quantidadeEstoque,
    );
    return PdvConsultaPreviewPanel(
      produto: linha.produto,
      precoListaAtivo: linha.precoTipo,
      precoUnitarioDe: _precoExibicaoConsulta,
      rotuloPreco: _rotuloPreco,
      formatarMoeda: _formatarMoeda,
      estoqueCritico: _estoqueCriticoPdv(linha.produto),
      compacto: compacto,
      mostrarDescricaoInline: true,
      tituloPainel: 'Item no carrinho',
      campanhaPromo: campanhas.isNotEmpty ? campanhas.first : null,
      promocaoAtiva: _resolverPrecoProduto(
        linha.produto,
        precoTipoLista: linha.precoTipo,
        quantidade: linha.quantidadeEstoque,
      ),
      quantidadeNoOrcamento: _quantidadeProdutoNoCarrinho(linha.produto.id),
      precoUnitarioLinha: linha.precoUnitario,
      precoUnitarioManual: linha.precoUnitarioManual,
      onAlterarPreco: () => unawaited(_alterarPrecoLinhaCarrinhoSelecionada()),
      onDetalhes: () => unawaited(_abrirDetalhesProdutoCarrinho()),
    );
  }

  Widget _buildAreaCarrinhoComPreviewPdv() {
    if (_carrinho.isEmpty || _linhaCarrinhoSelecionada == null) {
      return _buildPainelCheckoutPdv();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final painel = _buildPainelCheckoutPdv();
        final lateral = constraints.maxWidth >= _breakpointPreviewCarrinhoPdv;
        if (lateral) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: painel),
              SizedBox(
                width: _larguraPreviewCarrinhoPdv,
                child: _buildPreviewCarrinhoPdv(compacto: false),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 360,
              child: _buildPreviewCarrinhoPdv(compacto: true),
            ),
            const SizedBox(height: 8),
            Expanded(child: painel),
          ],
        );
      },
    );
  }

  Widget _buildPainelCheckoutPdv() {
    return _PdvPainelCheckout(
      leiauteEmpilhado: true,
      keyPainel: _keyPainelCheckoutPdV,
      painelCheckoutRecolhido: false,
      carrinhoCount: _carrinho.length,
      totalResumoColapsado: _formatarMoeda(_totalGeralComFrete),
      onExpandirPainel: _irParaPesquisaProdutos,
      orcamentoEmEdicao: _orcamentoEmEdicaoId != null,
      orcamentoEmEdicaoNumero: _orcamentoEmEdicaoNumero?.toString(),
      ultimoOrcamentoSalvoNumero: _ultimoOrcamentoSalvoNumero,
      ultimoOrcamentoSalvoTotal: _ultimoOrcamentoSalvoTotal,
      onCancelarEdicaoOrcamento: () {
        setState(() {
          _orcamentoEmEdicaoId = null;
          _orcamentoEmEdicaoNumero = null;
        });
      },
      mostrarDicaAtalhosCarrinho: _mostrarAjudaAtalhos && _carrinho.isNotEmpty,
      resumoEntregaItens: _resumoEntregaItensCarrinho,
      carrinhoBody: _PdvCarrinhoProdutos(
        carrinhoFocus: _carrinhoFocus,
        onKeyCarrinho: _onKeyCarrinho,
        itens: _carrinho,
        indiceLinhaSelecionada: _indiceLinhaCarrinho,
        onSelecionarLinha: (index) {
          setState(() => _indiceLinhaCarrinho = index);
          _carrinhoFocus.requestFocus();
        },
        rotuloPreco: _rotuloPreco,
        formatarMoeda: _formatarMoeda,
        onAlterarQuantidade: _alterarQuantidadeCarrinho,
        onRemoverItem: _removerItemCarrinho,
        onAlternarTipoEntrega: _alternarTipoEntregaLinhaCarrinho,
        onDividirLinha: _dividirLinhaCarrinho,
        onAlterarPrecoLinha: _alterarPrecoLinhaCarrinho,
        onIrPesquisaQuandoVazio: () => unawaited(_abrirConsultaProdutos()),
        produtoExcedeEstoque: _produtoExcedeEstoqueNoCarrinho,
      ),
      subtotalProdutos: _totalOrcamento,
      valorFrete: _valorFreteAtual,
      valorDesconto: _valorDescontoReaisPdV(),
      descontoConfigAtivo: _maxDescontoPercentualPdv > 0.004,
      totalDestaqueValor: _maxDescontoPercentualPdv > 0.004
          ? _totalLiquidoPagamentoPdV()
          : _totalGeralComFrete,
      formatarMoeda: _formatarMoeda,
      onIrPesquisaProdutos: _irParaPesquisaProdutos,
      onRecolherCheckout: _irParaPesquisaProdutos,
      focusSalvarOrcamento: _focusSalvarOrcamentoPdV,
      onContinuarFechamento: () {
        unawaited(_abrirPassoFechamentoVenda());
      },
      labelBotaoContinuar: _orcamentoEmEdicaoId != null
          ? 'Continuar para atualizar (F10)'
          : 'Continuar para salvar (F10)',
    );
  }

  String? get _segmentoClienteAtivo {
    final id = _clienteSelecionadoId;
    if (id == null || id <= 0) return null;
    return widget.clienteRepository.obterPorId(id)?.segmento;
  }

  String _normalizarTabelaPrecoPdv(String? valor) {
    switch (valor) {
      case 'preco2':
      case 'preco3':
        return valor!;
      case 'preco1':
      default:
        return 'preco1';
    }
  }

  /// Atualiza [_precoListaAtivo] e recalcula precos de todas as linhas do carrinho.
  void _atualizarPrecosCarrinhoComTabela(String novaTabela) {
    final tabela = _normalizarTabelaPrecoPdv(novaTabela);
    _precoListaAtivo = tabela;
    if (_carrinho.isEmpty) return;
    for (final linha in _carrinho) {
      if (linha.precoUnitarioManual) continue;
      final r = _resolverPrecoProduto(
        linha.produto,
        precoTipoLista: tabela,
        quantidade: linha.quantidadeEstoque,
      );
      linha.precoUnitario = r.precoFinal;
      linha.precoTipo = r.precoTipo;
      linha.promocaoId = r.promocaoId;
      linha.promocaoNome = r.promocaoNome;
    }
    _promoCarrinho.aplicarRegrasCarrinho(
      _carrinho,
      dataReferencia: DateTime.now(),
      segmentoCliente: _segmentoClienteAtivo,
    );
  }

  void _aplicarSugestaoFormaPagamentoPorTabela(
    String tabela, {
    bool preservarSelecaoAtual = false,
  }) {
    final opcoes = _opcoesFormaPagamentoPdVParaTabela(tabela);
    if (opcoes.isEmpty) return;
    final ids = opcoes.map((o) => o.id).toSet();

    if (!preservarSelecaoAtual && tabela == 'preco1') {
      final credito =
          ids.contains('cartao_credito') ? 'cartao_credito' : opcoes.first.id;
      _formaPagamentoSelecionada = credito;
      if (credito != 'cartao_credito') {
        _parcelasSelecionadas = 1;
      }
      return;
    }

    if (ids.contains(_formaPagamentoSelecionada)) return;
    _formaPagamentoSelecionada = opcoes.first.id;
    if (_formaPagamentoSelecionada != 'cartao_credito') {
      _parcelasSelecionadas = 1;
    }
  }

  void _definirTabelaPrecoPdv(String novaTabela) {
    final tabela = _normalizarTabelaPrecoPdv(novaTabela);
    if (tabela == _precoListaAtivo) return;
    setState(() {
      _atualizarPrecosCarrinhoComTabela(tabela);
      _aplicarSugestaoFormaPagamentoPorTabela(tabela);
    });
  }

  void _atualizarEntregaCarrinhoComTipo(String novoTipo) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(novoTipo);
    _tipoEntregaSelecionada = tipo;
    for (final linha in _carrinho) {
      linha.tipoEntregaItem = tipo;
    }
  }

  void _definirEntregaPadraoPdv(String novoTipo) {
    final tipo = EntregaVendaHelper.normalizarTipoItem(novoTipo);
    if (tipo ==
        EntregaVendaHelper.normalizarTipoItem(_tipoEntregaSelecionada)) {
      return;
    }
    setState(() => _atualizarEntregaCarrinhoComTipo(tipo));
  }

  void _recalcularPromocoesCarrinho() {
    if (_carrinho.isEmpty) return;
    _atualizarPrecosCarrinhoComTabela(_precoListaAtivo);
  }

  PromocaoPrecoResult _resolverPrecoProduto(
    Produto produto, {
    String? precoTipoLista,
    int quantidade = 1,
    DateTime? dataReferencia,
  }) {
    return _promoPreco.resolver(
      produto,
      dataReferencia: dataReferencia ?? DateTime.now(),
      quantidade: quantidade,
      precoTipoLista: precoTipoLista ?? _precoListaAtivo,
      segmentoCliente: _segmentoClienteAtivo,
    );
  }

  double _precoExibicaoConsulta(Produto produto, String precoTipo) {
    return _resolverPrecoProduto(
      produto,
      precoTipoLista: precoTipo,
    ).precoFinal;
  }

  String _rotuloPreco(String precoTipo) {
    switch (precoTipo) {
      case PromocaoCadastro.precoTipoPromo:
        return 'Promocao';
      case 'preco2':
        return 'À Vista';
      case 'preco3':
        return 'Atacado';
      case 'preco1':
      default:
        return 'A Prazo';
    }
  }

  Produto _produtoAtualizadoParaPdv(Produto produto) =>
      widget.produtoRepository.obterPorId(produto.id) ?? produto;

  Future<void> _adicionarAoOrcamento(Produto produto) async {
    final produtoAtual = _produtoAtualizadoParaPdv(produto);
    final result = await showDialog<_AdicionarOrcamentoResult>(
      context: context,
      builder: (context) => _AdicionarAoOrcamentoDialog(
        produtoRepository: widget.produtoRepository,
        produto: produtoAtual,
        precoTipoInicial: _precoListaAtivo,
        tipoEntregaInicial: _tipoEntregaSelecionada,
        precoUnitarioDe: (p, t) =>
            _resolverPrecoProduto(p, precoTipoLista: t).precoFinal,
        formatarMoeda: _formatarMoeda,
      ),
    );

    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (result.quantidadeVenda <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    await _adicionarComQuantidade(
      _produtoAtualizadoParaPdv(produto),
      result.quantidadeVenda,
      precoTipo: result.precoTipo,
      tipoEntregaItem: result.tipoEntregaItem,
      quantidadeEmUnidadeCompra: result.quantidadeEmUnidadeCompra,
    );
  }

  static const List<({String id, String rotulo, IconData icone})>
      _opcoesFormaPagamentoPdV = [
    (id: 'dinheiro', rotulo: 'Dinheiro', icone: Icons.payments_outlined),
    (id: 'pix', rotulo: 'PIX', icone: Icons.qr_code_2_outlined),
    (
      id: 'cartao_debito',
      rotulo: 'Debito',
      icone: Icons.credit_card_outlined,
    ),
    (
      id: 'cartao_credito',
      rotulo: 'Credito',
      icone: Icons.credit_score_outlined,
    ),
    (id: 'transferencia', rotulo: 'Transfer.', icone: Icons.account_balance_outlined),
    (id: 'fiado', rotulo: 'Fiado', icone: Icons.receipt_long_outlined),
  ];

  static const Map<String, List<String>> _meiosPagamentoPorTabelaPdv = {
    'preco1': ['cartao_credito', 'fiado'],
    'preco2': ['pix', 'dinheiro', 'cartao_debito'],
    'preco3': ['dinheiro', 'pix', 'cartao_debito'],
  };

  List<({String id, String rotulo, IconData icone})>
      _opcoesFormaPagamentoPdVParaTabela(String tabela) {
    final ids = _meiosPagamentoPorTabelaPdv[tabela] ??
        _meiosPagamentoPorTabelaPdv['preco1']!;
    final opcoes = <({String id, String rotulo, IconData icone})>[];
    for (final id in ids) {
      if (id == 'fiado' && !_podeVenderFiado) continue;
      for (final op in _opcoesFormaPagamentoPdV) {
        if (op.id == id) {
          opcoes.add(op);
          break;
        }
      }
    }
    return opcoes;
  }

  List<({String id, String rotulo, IconData icone})>
      _opcoesFormaPagamentoPdVAtivas() =>
          _opcoesFormaPagamentoPdVParaTabela(_precoListaAtivo);

  bool _podeSelecionarMeioMistoFiado(String meioAtualLinha) {
    if (meioAtualLinha == 'fiado') return true;
    return !_linhasPagamentoMisto.any((l) => l.meio == 'fiado');
  }

  void _selecionarMeioPagamentoMisto({
    required _LinhaPagamentoMistoPdV linha,
    required String meio,
    required StateSetter setDialogState,
  }) {
    if (meio == 'fiado' && !_podeVenderFiado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissao para vender a prazo (fiado).'),
        ),
      );
      return;
    }
    if (meio == 'fiado' && !_podeSelecionarMeioMistoFiado(linha.meio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento misto: use apenas uma linha Fiado.'),
        ),
      );
      return;
    }
    _atualizarCheckoutFechamento(setDialogState, () {
      linha.meio = meio;
      if (meio != 'cartao_credito') linha.parcelas = 1;
    });
  }

  Widget _buildChipFormaPagamento({
    required String rotulo,
    required IconData icone,
    required bool selecionado,
    required bool destacadoTeclado,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 17),
          const SizedBox(width: 5),
          Text(rotulo),
        ],
      ),
      selected: selecionado,
      side: destacadoTeclado && !selecionado
          ? BorderSide(color: scheme.primary, width: 2)
          : null,
      onSelected: onTap == null ? null : (_) => onTap(),
    );
  }

  Widget _buildChipsFormaPagamentoCheckout(StateSetter setDialogState) {
    final theme = Theme.of(context);
    final pagamentoComFoco = _focusPagamentoPdV.hasFocus;
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    final atalhos =
        opcoes.length <= 1 ? '1' : '1-${opcoes.length}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Forma de pagamento ($atalhos ou setas) · ${_rotuloPreco(_precoListaAtivo)}',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _focusPagamentoPdV,
          onFocusChange: (hasFocus) {
            if (!hasFocus) return;
            final idx = _indiceFormaPagamentoSelecionadaPdV();
            if (_indiceChipPagamentoFocado == idx) return;
            _indiceChipPagamentoFocado = idx;
            _checkoutDialogSetState?.call(() {});
          },
          onKeyEvent: (node, event) =>
              _onKeyPagamentoCheckout(node, event, setDialogState),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < opcoes.length; i++)
                _buildChipFormaPagamento(
                  rotulo: opcoes[i].rotulo,
                  icone: opcoes[i].icone,
                  selecionado: _formaPagamentoSelecionada == opcoes[i].id,
                  destacadoTeclado:
                      pagamentoComFoco && _indiceChipPagamentoFocado == i,
                  onTap: () => _aplicarFormaPagamentoPorIndice(i, setDialogState),
                ),
            ],
          ),
        ),
        if (_formaPagamentoSelecionada == 'fiado') ...[
          const SizedBox(height: 8),
          Text(
            'O caixa finaliza a venda; o cliente quita as parcelas depois.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_formaPagamentoSelecionada == 'cartao_credito') ...[
          const SizedBox(height: 10),
          _buildChipsParcelasCreditoCheckout(setDialogState),
        ],
      ],
    );
  }

  Widget _buildChipsParcelasCreditoCheckout(StateSetter setDialogState) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parcelas no cartao',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Focus(
          focusNode: _focusParcelasPdV,
          child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(12, (i) {
            final n = i + 1;
            return ChoiceChip(
              label: Text(
                _rotuloParcelaCreditoValor(n, _totalLiquidoPagamentoPdV()),
              ),
              selected: _parcelasSelecionadas == n,
              onSelected: (_) {
                _atualizarCheckoutFechamento(
                  setDialogState,
                  () => _parcelasSelecionadas = n,
                );
              },
            );
          }),
        ),
        ),
        const SizedBox(height: 4),
        Text(
          _rotuloParcela(_parcelasSelecionadas),
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildChipsMeioMistoLinha({
    required _LinhaPagamentoMistoPdV linha,
    required StateSetter setDialogState,
  }) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final op in _opcoesFormaPagamentoPdVAtivas())
          _buildChipFormaPagamento(
            rotulo: op.rotulo,
            icone: op.icone,
            selecionado: linha.meio == op.id,
            destacadoTeclado: false,
            onTap: (op.id == 'fiado' && !_podeVenderFiado) ||
                    (op.id == 'fiado' &&
                        !_podeSelecionarMeioMistoFiado(linha.meio))
                ? null
                : () => _selecionarMeioPagamentoMisto(
                      linha: linha,
                      meio: op.id,
                      setDialogState: setDialogState,
                    ),
          ),
      ],
    );
  }

  Widget _buildPainelPagamentoMistoPdV(StateSetter setDialogState) {
    final restante = _totalLiquidoPagamentoPdV() - _somaDigitadaMistoPdV();
    final ok = restante.abs() < 0.02;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_linhasPagamentoMisto.length, (i) {
          final linha = _linhasPagamentoMisto[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Parte ${i + 1}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Remover parte',
                        visualDensity: VisualDensity.compact,
                        onPressed: _linhasPagamentoMisto.length <= 2
                            ? null
                            : () {
                                _atualizarCheckoutFechamento(setDialogState, () {
                                  final rem = _linhasPagamentoMisto.removeAt(i);
                                  rem.dispose();
                                });
                              },
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                    ],
                  ),
                  _buildChipsMeioMistoLinha(
                    linha: linha,
                    setDialogState: setDialogState,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: linha.valorController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor R\$',
                            hintText: '0,00',
                            isDense: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      if (linha.meio == 'cartao_credito') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final valorLinha = _parseValorMonetario(
                                linha.valorController.text,
                              );
                              return DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: linha.parcelas.clamp(1, 12),
                                decoration: const InputDecoration(
                                  labelText: 'Parc. credito',
                                  isDense: true,
                                ),
                                selectedItemBuilder: (context) {
                                  return List.generate(12, (k) {
                                    final n = k + 1;
                                    return Align(
                                      alignment: AlignmentDirectional.centerStart,
                                      child: Text(
                                        _rotuloParcelaCreditoValor(
                                          n,
                                          valorLinha,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                      ),
                                    );
                                  });
                                },
                                items: List.generate(
                                  12,
                                  (k) {
                                    final n = k + 1;
                                    return DropdownMenuItem(
                                      value: n,
                                      child: Text(
                                        _rotuloParcelaCreditoValor(
                                          n,
                                          valorLinha,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                onChanged: (p) {
                                  if (p != null) {
                                    _atualizarCheckoutFechamento(
                                      setDialogState,
                                      () => linha.parcelas = p,
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              _atualizarCheckoutFechamento(setDialogState, () {
                _linhasPagamentoMisto.add(
                  _LinhaPagamentoMistoPdV(
                    meio: 'cartao_credito',
                    valorController: TextEditingController(),
                    parcelas: 1,
                  ),
                );
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Adicionar meio'),
          ),
        ),
        if (_valorFiadoCheckoutPdV() > 0.001) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Parte fiado: ${_formatarMoeda(_valorFiadoCheckoutPdV())}. '
              'Vincule o cliente e defina as parcelas de quitação abaixo. '
              'No caixa, só entra o que o cliente paga agora (dinheiro, PIX, cartão).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        Text(
          ok
              ? 'Pagamento fecha com o total geral.'
              : 'Restante: ${_formatarMoeda(restante)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: ok
                ? Colors.green.shade800
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  int _indiceFormaPagamentoSelecionadaPdV() {
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    final idx = opcoes.indexWhere((o) => o.id == _formaPagamentoSelecionada);
    return idx >= 0 ? idx : 0;
  }

  void _sincronizarIndiceChipPagamentoComSelecao() {
    _indiceChipPagamentoFocado = _indiceFormaPagamentoSelecionadaPdV();
  }

  void _aplicarFormaPagamentoPorIndice(
    int index,
    StateSetter setDialogState,
  ) {
    final opcoes = _opcoesFormaPagamentoPdVAtivas();
    if (index < 0 || index >= opcoes.length) return;
    final op = opcoes[index];
    if (op.id == 'fiado' && !_podeVenderFiado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem permissao para vender a prazo (fiado).'),
        ),
      );
      return;
    }
    _atualizarCheckoutFechamento(setDialogState, () {
      _formaPagamentoSelecionada = op.id;
      _indiceChipPagamentoFocado = index;
      if (op.id != 'cartao_credito') {
        _parcelasSelecionadas = 1;
      }
    });
    if (op.id == 'cartao_credito' && _checkoutDialogAberto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusParcelasPdV.requestFocus();
      });
    }
  }

  KeyEventResult _onKeyPagamentoCheckout(
    FocusNode node,
    KeyEvent event,
    StateSetter setDialogState,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_pagamentoMistoPdV) return KeyEventResult.ignored;
    final key = event.logicalKey;

    int? indiceTeclaNumerica;
    if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      indiceTeclaNumerica = 0;
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      indiceTeclaNumerica = 1;
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      indiceTeclaNumerica = 2;
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      indiceTeclaNumerica = 3;
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      indiceTeclaNumerica = 4;
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      indiceTeclaNumerica = 5;
    }

    if (indiceTeclaNumerica != null) {
      _aplicarFormaPagamentoPorIndice(indiceTeclaNumerica, setDialogState);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      final opcoes = _opcoesFormaPagamentoPdVAtivas();
      final next = (_indiceChipPagamentoFocado + 1) % opcoes.length;
      _aplicarFormaPagamentoPorIndice(next, setDialogState);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      final opcoes = _opcoesFormaPagamentoPdVAtivas();
      final prev =
          (_indiceChipPagamentoFocado - 1 + opcoes.length) % opcoes.length;
      _aplicarFormaPagamentoPorIndice(prev, setDialogState);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _aplicarFormaPagamentoPorIndice(
        _indiceChipPagamentoFocado,
        setDialogState,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _aplicarFocoInicialCheckoutDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_checkoutDialogAberto || !mounted) return;
      if (_pagamentoMistoPdV && _checkoutMaisOpcoesExpandido) {
        _focusPagamentoMistoSwitchPdV.requestFocus();
        return;
      }
      _sincronizarIndiceChipPagamentoComSelecao();
      _focusPagamentoPdV.requestFocus();
    });
  }

  void _checkoutDialogFecharOuRetroceder() {
    final ctx = _checkoutDialogFechamentoContext;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  void _toggleCheckoutMaisOpcoes(StateSetter setDialogState) {
    _atualizarCheckoutFechamento(
      setDialogState,
      () => _checkoutMaisOpcoesExpandido = !_checkoutMaisOpcoesExpandido,
    );
    _aplicarFocoInicialCheckoutDialog();
  }

  void _toggleCheckoutMaisOpcoesDialogoAberto() {
    final setDialogState = _checkoutDialogSetState;
    if (setDialogState == null) return;
    _toggleCheckoutMaisOpcoes(setDialogState);
  }

  String? _mensagemErroConfirmarCheckout() {
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      return _mensagemErroDescontoPdVUltrapassaTeto();
    }
    if (_precisaPlanoFiadoPdV() &&
        (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0)) {
      return 'Selecione o cliente no topo da tela (fiado).';
    }
    if (_carrinhoTemItemCarreto &&
        _enderecoEntregaController.text.trim().isEmpty) {
      return 'Informe o endereco para carreto.';
    }
    if (_carrinhoTemItemCarreto && _dataEntregaMarcada == null) {
      return 'Defina a data combinada da entrega com o cliente.';
    }
    if (_carrinhoTemItemCarreto &&
        _prioridadeEntregaSelecionada == 'agendada' &&
        _janelaEntregaSelecionada == 'nao_definida') {
      return 'Para entrega agendada, selecione janela Manha ou Tarde.';
    }
    return null;
  }

  Future<void> _confirmarCheckoutEEnviar({
    BuildContext? fechamentoDialogContext,
  }) async {
    if (_salvandoOrcamento) return;
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      final ok = await _solicitarAutorizacaoDescontoAcimaTetoPdV();
      if (!ok || !mounted) return;
      _checkoutDialogSetState?.call(() {});
    }
    final erro = _mensagemErroConfirmarCheckout();
    if (erro != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro)),
      );
      return;
    }
    await _salvarOrcamento(fechamentoDialogContext: fechamentoDialogContext);
  }

  Future<void> _checkoutDialogAcaoF10Async() async {
    if (!_checkoutDialogAberto || _salvandoOrcamento) return;
    final ctx = _checkoutDialogFechamentoContext;
    if (ctx == null) return;
    await _confirmarCheckoutEEnviar(fechamentoDialogContext: ctx);
  }

  Widget _buildCheckoutDicaAtalhosTeclado() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'F10 enviar · 1-6 pagamento · F3 desconto · F6 misto',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _abrirPassoFechamentoVenda() async {
    _descontoPdVController.clear();
    _tipoDescontoPdV = 'percentual';
    _descontoAcimaTetoAutorizadoPdv = false;
    _descontoAutorizadoPorPdV = null;
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    _aplicarEnderecoCarretoDoClienteSeVazio();
    _aplicarSugestaoFormaPagamentoPorTabela(
      _precoListaAtivo,
      preservarSelecaoAtual: _orcamentoEmEdicaoId != null,
    );
    _checkoutMaisOpcoesExpandido =
        _pagamentoMistoPdV || _orcamentoEmEdicaoId != null;
    final scrollCheckout = ScrollController();
    _checkoutDialogAberto = true;
    _checkoutDialogFocoInicialAplicado = false;
    _checkoutDialogScroll = scrollCheckout;
    try {
      await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            _checkoutDialogSetState = setDialogState;
            _checkoutDialogFechamentoContext = dialogContext;
            if (!_checkoutDialogFocoInicialAplicado) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_checkoutDialogAberto ||
                    !mounted ||
                    _checkoutDialogFocoInicialAplicado) {
                  return;
                }
                _checkoutDialogFocoInicialAplicado = true;
                _aplicarFocoInicialCheckoutDialog();
              });
            }
            return AlertDialog(
              title: Text(
                _orcamentoEmEdicaoId != null
                    ? 'Concluir atualizacao da venda'
                    : 'Dados para enviar ao caixa',
              ),
              content: AdaptiveDialogPane(
                desktopWidth: 560,
                desktopHeight: (MediaQuery.sizeOf(context).height * 0.55)
                    .clamp(380.0, 520.0),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    visualDensity: VisualDensity.compact,
                    inputDecorationTheme: Theme.of(context)
                        .inputDecorationTheme
                        .copyWith(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCheckoutResumoFixo(
                        setDialogState,
                        dialogContext: dialogContext,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Scrollbar(
                          controller: scrollCheckout,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          child: SingleChildScrollView(
                            controller: scrollCheckout,
                            primary: false,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              right: 8,
                              bottom: 120,
                            ),
                            child: FocusTraversalGroup(
                              policy: OrderedTraversalPolicy(),
                              child: _buildFormularioFechamentoVenda(
                                setDialogState: setDialogState,
                                scrollCheckout: scrollCheckout,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildCheckoutDicaAtalhosTeclado(),
                    ],
                  ),
                ),
              ),
              actions: _buildCheckoutDialogActions(
                dialogContext: dialogContext,
                setDialogState: setDialogState,
                scrollCheckout: scrollCheckout,
              ),
            );
          },
        );
      },
    );
    } finally {
      _checkoutDialogAberto = false;
      _checkoutDialogFocoInicialAplicado = false;
      _checkoutDialogSetState = null;
      _checkoutDialogFechamentoContext = null;
      _checkoutDialogScroll = null;
      scrollCheckout.dispose();
      if (mounted &&
          !_salvandoOrcamento &&
          !_dialogoOrcamentoSalvoAberto) {
        _aplicarFocoInicialPdv();
      }
    }
  }

  /// Atualiza estado do checkout e redesenha apenas o dialog (StatefulBuilder).
  void _atualizarCheckoutFechamento(
    StateSetter setDialogState,
    VoidCallback fn, {
    ScrollController? scrollCheckout,
  }) {
    fn();
    if (_pagamentoMistoPdV || _precisaPlanoFiadoPdV()) {
      _checkoutMaisOpcoesExpandido = true;
    }
    setDialogState(() {});
    if (scrollCheckout != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollCheckout.hasClients) return;
        final max = scrollCheckout.position.maxScrollExtent;
        if (scrollCheckout.offset > max) {
          scrollCheckout.jumpTo(max);
        }
      });
    }
  }

  List<Widget> _buildCheckoutDialogActions({
    required BuildContext dialogContext,
    required StateSetter setDialogState,
    required ScrollController scrollCheckout,
  }) {
    final confirmarLabel = _orcamentoEmEdicaoId != null
        ? 'Confirmar atualizacao'
        : 'Enviar ao caixa';

    return [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Fechar (Esc)'),
      ),
      Focus(
        focusNode: _focusCheckoutAcaoPrimaria,
        child: FilledButton.icon(
          onPressed: () => unawaited(
            _confirmarCheckoutEEnviar(fechamentoDialogContext: dialogContext),
          ),
          icon: const Icon(Icons.point_of_sale_outlined),
          label: Text('$confirmarLabel (F10)'),
        ),
      ),
    ];
  }

  Widget _buildCheckoutBannerEdicao(StateSetter setDialogState) {
    if (_orcamentoEmEdicaoId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Editando venda ${_orcamentoEmEdicaoNumero ?? '-'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          TextButton(
            onPressed: () {
              _atualizarCheckoutFechamento(setDialogState, () {
                _orcamentoEmEdicaoId = null;
                _orcamentoEmEdicaoNumero = null;
              });
            },
            child: const Text('Cancelar edicao'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutResumoLinhaItens() {
    final theme = Theme.of(context);
    return Text(
      '${_carrinho.length} ${_carrinho.length == 1 ? 'item' : 'itens'}'
      '${_resumoEntregaItensCarrinho.isNotEmpty ? ' · $_resumoEntregaItensCarrinho' : ''}',
      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildCheckoutPainelFiado(StateSetter setDialogState) {
    if (!_precisaPlanoFiadoPdV()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanoFiadoPdvPanel(
            key: ValueKey(_valorFiadoCheckoutPdV().toStringAsFixed(2)),
            valorFiado: _valorFiadoCheckoutPdV(),
            parcelasIniciais: _planoFiadoParcelas,
            onChanged: (parcelas) {
              _atualizarCheckoutFechamento(
                setDialogState,
                () => _planoFiadoParcelas = parcelas,
              );
            },
          ),
          _buildResumoLimiteCreditoCheckoutPdV(),
        ],
      ),
    );
  }

  Widget _buildCheckoutMaisOpcoes({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _toggleCheckoutMaisOpcoes(setDialogState),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _checkoutMaisOpcoesExpandido
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pagamento misto (F6)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_pagamentoMistoPdV)
                    Chip(
                      label: const Text('Misto'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_checkoutMaisOpcoesExpandido) ...[
          const SizedBox(height: 8),
          Focus(
            focusNode: _focusPagamentoMistoSwitchPdV,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _pagamentoMistoPdV,
              onChanged: (on) {
                _atualizarCheckoutFechamento(
                  setDialogState,
                  () {
                    _pagamentoMistoPdV = on;
                    if (on) {
                      _inicializarLinhasMistoPadrao();
                      _checkoutMaisOpcoesExpandido = true;
                    } else {
                      _disposeLinhasPagamentoMisto();
                    }
                  },
                  scrollCheckout: scrollCheckout,
                );
              },
              title: const Text('Dividir pagamento (misto)'),
              subtitle: const Text(
                'Ex.: parte em dinheiro e parte em fiado',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_pagamentoMistoPdV) ...[
            const SizedBox(height: 4),
            _buildPainelPagamentoMistoPdV(setDialogState),
          ],
        ],
      ],
    );
  }

  Widget _buildCheckoutSecaoEntrega({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    return _buildSecaoCheckoutDialog(
      titulo: 'Entrega',
      icone: Icons.local_shipping_outlined,
      children: [
        Text(
          _resumoEntregaItensCarrinho.isEmpty
              ? 'Sem itens com entrega definida'
              : _resumoEntregaItensCarrinho,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        if (_carrinhoEntregaMista) ...[
          const SizedBox(height: 4),
          Text(
            'Venda com tipos de entrega mistos',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
        if (_carrinhoTemItemCarreto) ...[
          const SizedBox(height: 10),
          const SizedBox(height: 8),
          if (_clienteSelecionado() != null &&
              _enderecosClienteSelecionado().isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _indiceEnderecoSelecionado.clamp(
                0,
                _enderecosClienteSelecionado().length - 1,
              ),
              decoration: const InputDecoration(
                labelText: 'Endereco para entrega',
              ),
              selectedItemBuilder: (context) {
                final enderecos = _enderecosClienteSelecionado();
                return List.generate(enderecos.length, (index) {
                  final endereco = enderecos[index];
                  final rotulo = endereco.tituloExibicao();
                  final resumo = endereco.resumo();
                  final texto =
                      resumo.isEmpty ? rotulo : '$rotulo — $resumo';
                  return Tooltip(
                    message: texto,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        texto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  );
                });
              },
              items: List.generate(_enderecosClienteSelecionado().length, (
                index,
              ) {
                final endereco = _enderecosClienteSelecionado()[index];
                final rotulo = endereco.tituloExibicao();
                final resumo = endereco.resumo();
                return DropdownMenuItem<int>(
                  value: index,
                  child: Text(
                    resumo.isEmpty ? rotulo : '$rotulo — $resumo',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                );
              }),
              onChanged: (value) {
                if (value == null) return;
                final cliente = _clienteSelecionado();
                if (cliente == null) return;
                _atualizarCheckoutFechamento(setDialogState, () {
                  _aplicarEnderecoSelecionadoDoCliente(cliente, value);
                });
              },
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _prioridadeEntregaSelecionada,
                  decoration: const InputDecoration(
                    labelText: 'Prioridade da entrega',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
                    DropdownMenuItem(
                      value: 'agendada',
                      child: Text('Agendada'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _atualizarCheckoutFechamento(setDialogState, () {
                      _prioridadeEntregaSelecionada = value;
                      if (_prioridadeEntregaSelecionada == 'agendada' &&
                          _janelaEntregaSelecionada == 'nao_definida') {
                        _janelaEntregaSelecionada = 'manha';
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _janelaEntregaSelecionada,
                  decoration: const InputDecoration(labelText: 'Janela'),
                  items: const [
                    DropdownMenuItem(
                      value: 'nao_definida',
                      child: Text('Nao definida'),
                    ),
                    DropdownMenuItem(value: 'manha', child: Text('Manha')),
                    DropdownMenuItem(value: 'tarde', child: Text('Tarde')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _atualizarCheckoutFechamento(
                      setDialogState,
                      () => _janelaEntregaSelecionada = value,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final agora = DateTime.now();
                final inicial = _dataEntregaMarcada ?? agora;
                final escolhido = await showDatePicker(
                  context: context,
                  initialDate: inicial,
                  firstDate: DateTime(agora.year, agora.month, agora.day),
                  lastDate: DateTime(agora.year + 3, 12, 31),
                );
                if (!mounted || escolhido == null) return;
                _atualizarCheckoutFechamento(
                  setDialogState,
                  () => _dataEntregaMarcada = escolhido,
                );
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _dataEntregaMarcada == null
                    ? 'Definir data da entrega'
                    : 'Data da entrega: ${DateFormat('dd/MM/yyyy').format(_dataEntregaMarcada!)}',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entrega configurada',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _resumoEntrega(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Focus(
                    focusNode: _focusEditarEntregaPdV,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final cliente = _clienteSelecionado();
                        if (cliente == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Selecione um cliente para editar a entrega.',
                              ),
                            ),
                          );
                          return;
                        }
                        final entrega = await _abrirDialogEntregaCliente(
                          cliente: cliente,
                        );
                        if (!mounted || entrega == null) return;
                        _atualizarCheckoutFechamento(setDialogState, () {
                          _atualizarEntregaCarrinhoComTipo(
                            EntregaVendaHelper.tipoEntregaLoja,
                          );
                          _dataEntregaMarcada ??= DateTime.now();
                          _valorFreteController.text = entrega.valorFrete;
                          _enderecoEntregaController.text = entrega.endereco;
                          _observacaoEntregaController.text =
                              entrega.observacao;
                          _indiceEnderecoSelecionado =
                              entrega.indiceEnderecoSelecionado;
                        });
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar dados da entrega'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  double _valorEntraCaixaAgoraPdV() {
    final total = _totalLiquidoPagamentoPdV();
    final fiado = _valorFiadoCheckoutPdV();
    return (total - fiado).clamp(0.0, double.infinity).toDouble();
  }

  Widget _buildSecaoCheckoutDialog({
    required String titulo,
    required IconData icone,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCheckoutResumoFixo(
    StateSetter setDialogState, {
    required BuildContext dialogContext,
  }) {
    final theme = Theme.of(context);
    final total = _totalLiquidoPagamentoPdV();
    final fiado = _valorFiadoCheckoutPdV();
    final agora = _valorEntraCaixaAgoraPdV();
    final desconto = _valorDescontoReaisPdV();
    final confirmarLabel = _orcamentoEmEdicaoId != null
        ? 'Atualizar'
        : 'Enviar';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total a pagar (caixa)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatarMoeda(total),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => unawaited(
                  _confirmarCheckoutEEnviar(
                    fechamentoDialogContext: dialogContext,
                  ),
                ),
                icon: const Icon(Icons.point_of_sale_outlined, size: 20),
                label: Text('$confirmarLabel (F10)'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Subtotal ${_formatarMoeda(_totalOrcamento)} · '
            'Frete ${_formatarMoeda(_valorFreteAtual)}'
            '${desconto > 0.004 ? ' · Desconto -${_formatarMoeda(desconto)}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          if (fiado > 0.001) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _chipResumoCheckout(
                    rotulo: 'No caixa agora',
                    valor: agora,
                    destaque: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _chipResumoCheckout(
                    rotulo: 'Fiado (a receber)',
                    valor: fiado,
                    destaque: false,
                  ),
                ),
              ],
            ),
          ],
          if (_maxDescontoPercentualPdv > 0) ...[
            const SizedBox(height: 10),
            _buildCheckoutCampoDesconto(setDialogState),
          ],
        ],
      ),
    );
  }

  Widget _chipResumoCheckout({
    required String rotulo,
    required double valor,
    required bool destaque,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: destaque
            ? theme.colorScheme.surface
            : theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: theme.textTheme.labelSmall),
          Text(
            _formatarMoeda(valor),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutCampoDesconto(StateSetter setDialogState) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'percentual', label: Text('%')),
              ButtonSegment<String>(value: 'valor', label: Text('R\$')),
            ],
            selected: {_tipoDescontoPdV},
            onSelectionChanged: (values) {
              _atualizarCheckoutFechamento(setDialogState, () {
                _tipoDescontoPdV = values.first;
                _descontoPdVController.clear();
                _resetarAutorizacaoDescontoAcimaTetoPdV();
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                focusNode: _focusDescontoPdV,
                controller: _descontoPdVController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _tipoDescontoPdV == 'percentual'
                      ? 'Desconto %'
                      : 'Desconto R\$',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.92),
                  helperText: _descontoAcimaTetoAutorizadoPdv
                      ? 'Autorizado por $_descontoAutorizadoPorPdV'
                      : (_descontoPdVUltrapassaTetoSemAutorizacao()
                          ? 'Autorize um gerente para concluir'
                          : 'F3 · Max. ${_percentualMaximoEfetivoDescontoPdV().toStringAsFixed(1)}% '
                                '(${_formatarMoeda(_valorMaximoDescontoReaisPdV())})'),
                  errorText: _descontoPdVUltrapassaTetoSemAutorizacao()
                      ? _mensagemErroDescontoPdVUltrapassaTeto()
                      : null,
                  isDense: true,
                ),
                onChanged: (_) => _atualizarCheckoutFechamento(setDialogState, () {
                  _resetarAutorizacaoDescontoAcimaTetoPdV();
                }),
              ),
              if (_descontoPdVUltrapassaTetoSemAutorizacao())
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok = await _solicitarAutorizacaoDescontoAcimaTetoPdV();
                      if (ok) setDialogState(() {});
                    },
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: const Text('Autorizar gerente'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormularioFechamentoVenda({
    required StateSetter setDialogState,
    ScrollController? scrollCheckout,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCheckoutBannerEdicao(setDialogState),
        _buildCheckoutResumoLinhaItens(),
        const SizedBox(height: 10),
        if (_pagamentoMistoPdV)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Pagamento dividido — ajuste em Pagamento misto (F6).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          _buildChipsFormaPagamentoCheckout(setDialogState),
        _buildCheckoutPainelFiado(setDialogState),
        if (_precisaPlanoFiadoPdV() &&
            (_clienteSelecionadoId == null || _clienteSelecionadoId! <= 0)) ...[
          const SizedBox(height: 8),
          Text(
            'Fiado: selecione o cliente no topo da tela (Shift+F2).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_checkoutExibeSecaoEntrega) ...[
          const SizedBox(height: 12),
          _buildCheckoutSecaoEntrega(
            setDialogState: setDialogState,
            scrollCheckout: scrollCheckout,
          ),
        ],
        const SizedBox(height: 10),
        _buildCheckoutMaisOpcoes(
          setDialogState: setDialogState,
          scrollCheckout: scrollCheckout,
        ),
      ],
    );
  }

  Future<bool> _validarLimiteCreditoPdV({
    required int? clienteId,
    required double valorFiado,
  }) async {
    if (valorFiado <= 0.001) return true;
    if (clienteId == null || clienteId <= 0) return true;

    final r = widget.vendaRepository.validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiado,
      ignorarVendaId: _orcamentoEmEdicaoId,
    );
    if (r.permitido) return true;
    if (!mounted) return false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limite de credito'),
        content: Text(r.mensagem ?? 'Limite de credito excedido.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    return false;
  }

  Widget _buildResumoLimiteCreditoCheckoutPdV() {
    if (!_precisaPlanoFiadoPdV()) return const SizedBox.shrink();
    final clienteId = _clienteSelecionadoId;
    if (clienteId == null || clienteId <= 0) {
      return const SizedBox.shrink();
    }

    final valorFiado = _valorFiadoCheckoutPdV();
    final saldoAberto = widget.vendaRepository.saldoFiadoEmAbertoCliente(
      clienteId,
      ignorarVendaId: _orcamentoEmEdicaoId,
    );
    final cliente = widget.clienteRepository.obterPorId(clienteId);
    final limite = cliente?.limiteCredito ?? 0;
    if (limite <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final disponivelAgora =
        (limite - saldoAberto).clamp(0.0, double.infinity).toDouble();
    final r = widget.vendaRepository.validarLimiteCredito(
      clienteId: clienteId,
      valorFiadoOperacao: valorFiado,
      ignorarVendaId: _orcamentoEmEdicaoId,
    );

    if (r.permitido) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Credito: fiado em aberto ${LimiteCreditoHelper.formatarMoedaBr(saldoAberto)} '
          '· limite ${LimiteCreditoHelper.formatarMoedaBr(limite)} '
          '· disponivel ${LimiteCreditoHelper.formatarMoedaBr(disponivelAgora)} '
          '(fiado desta venda: ${LimiteCreditoHelper.formatarMoedaBr(valorFiado)})',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Text(
        r.mensagem ?? 'Limite de credito excedido.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  bool _validarClienteParaFiadoPdV({
    required int? clienteId,
    required DadosPagamentoOrcamento pagamento,
    required double totalVendaLiquido,
  }) {
    final valorFiado = LimiteCreditoHelper.valorFiadoNoPagamento(
      formaPagamento: pagamento.formaPagamento,
      totalVendaLiquido: totalVendaLiquido,
      linhasMisto: pagamento.linhasMisto,
    );
    if (valorFiado <= 0.001) return true;
    if (clienteId != null && clienteId > 0) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Vincule um cliente ao orcamento para usar pagamento fiado.',
        ),
      ),
    );
    return false;
  }

  /// Limpa a tela para a proxima venda (vendedor, cliente, carrinho, busca).
  void _prepararNovaVendaAposEnvioCaixa({
    int? numeroOrcamentoSalvo,
    double? totalOrcamentoSalvo,
  }) {
    setState(() {
      if (numeroOrcamentoSalvo != null && numeroOrcamentoSalvo > 0) {
        _ultimoOrcamentoSalvoNumero = numeroOrcamentoSalvo;
        _ultimoOrcamentoSalvoTotal = totalOrcamentoSalvo;
      }
      _carrinho.clear();
      _indiceLinhaCarrinho = null;
      _pagamentoMistoPdV = false;
      _disposeLinhasPagamentoMisto();
      _formaPagamentoSelecionada = 'dinheiro';
      _parcelasSelecionadas = 1;
      _planoFiadoParcelas = [];
      _clienteSelecionadoId = null;
      _indiceEnderecoSelecionado = 0;
      _vendedorSelecionadoId = null;
      _tipoEntregaSelecionada = EntregaVendaHelper.tipoRetirada;
      _prioridadeEntregaSelecionada = 'normal';
      _janelaEntregaSelecionada = 'nao_definida';
      _dataEntregaMarcada = null;
      _valorFreteController.clear();
      _enderecoEntregaController.clear();
      _observacaoEntregaController.clear();
      _orcamentoEmEdicaoId = null;
      _orcamentoEmEdicaoNumero = null;
      _descontoPdVController.clear();
      _tipoDescontoPdV = 'percentual';
      _resetarAutorizacaoDescontoAcimaTetoPdV();
      _pesquisaController.clear();
    });
    _sincronizarTextoBuscaClientePdv();
    _aplicarFocoInicialPdv();
  }

  Future<void> _salvarOrcamento({BuildContext? fechamentoDialogContext}) async {
    if (_salvandoOrcamento) return;
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    if (_descontoPdVUltrapassaTetoSemAutorizacao()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensagemErroDescontoPdVUltrapassaTeto())),
      );
      return;
    }
    _salvandoOrcamento = true;
    try {
      final valorFrete = _carrinhoTemItemCarreto
          ? _parseValorMonetario(_valorFreteController.text)
          : 0.0;
      if (_carrinhoTemItemCarreto &&
          _enderecoEntregaController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe o endereco para carreto.')),
        );
        return;
      }
      if (_carrinhoTemItemCarreto &&
          _prioridadeEntregaSelecionada == 'agendada' &&
          _janelaEntregaSelecionada == 'nao_definida') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para entrega agendada, selecione janela Manha ou Tarde.',
            ),
          ),
        );
        return;
      }
      if (_carrinhoTemItemCarreto && _dataEntregaMarcada == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Defina a data combinada da entrega com o cliente.'),
          ),
        );
        return;
      }
      if (valorFrete < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valor do frete nao pode ser negativo.'),
          ),
        );
        return;
      }
      if (_carrinhoTemItemCarreto && valorFrete <= 0) {
        if (!mounted) return;
        final aceitaGratis = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Frete zerado'),
            content: const Text(
              'Carreto com frete em R\$ 0,00. Confirma registrar entrega com frete gratuito, '
              'ou volte para informar o valor correto?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Informar frete'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Frete gratuito'),
              ),
            ],
          ),
        );
        if (aceitaGratis != true) {
          return;
        }
      }
      final itens = _carrinho
          .map(
            (item) => ItemVendaInput(
              produtoId: item.produto.id,
              quantidade: item.quantidade,
              precoUnitario: item.precoUnitario,
              precoTipo: item.precoTipo,
              tipoEntregaItem: item.tipoEntregaItem,
              promocaoId: item.promocaoId,
              promocaoNomeSnapshot: item.promocaoNome,
            ),
          )
          .toList();
      List<PagamentoOrcamentoLinha>? linhasMisto;
      try {
        linhasMisto = _montarLinhasMistoParaSalvar(_totalLiquidoPagamentoPdV());
      } on StateError catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      var pagamento = DadosPagamentoOrcamento(
        formaPagamento: _pagamentoMistoPdV
            ? 'misto'
            : _formaPagamentoSelecionada,
        quantidadeParcelas: _pagamentoMistoPdV
            ? 1
            : (_formaPagamentoSelecionada == 'cartao_credito'
                  ? _parcelasSelecionadas
                  : 1),
        linhasMisto: linhasMisto,
      );
      final totalLiquido = _totalLiquidoPagamentoPdV();
      if (!_validarClienteParaFiadoPdV(
        clienteId: _clienteSelecionadoId,
        pagamento: pagamento,
        totalVendaLiquido: totalLiquido,
      )) {
        return;
      }
      final valorFiado = LimiteCreditoHelper.valorFiadoNoPagamento(
        formaPagamento: pagamento.formaPagamento,
        totalVendaLiquido: totalLiquido,
        linhasMisto: linhasMisto,
      );
      if (valorFiado > 0.001 &&
          !PlanoFiadoCodec.validarContraValor(_planoFiadoParcelas, valorFiado)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Defina o plano de parcelas do fiado (valores e vencimentos) '
              'antes de salvar o orçamento.',
            ),
          ),
        );
        return;
      }
      if (!await _validarLimiteCreditoPdV(
        clienteId: _clienteSelecionadoId,
        valorFiado: valorFiado,
      )) {
        return;
      }
      pagamento = DadosPagamentoOrcamento(
        formaPagamento: pagamento.formaPagamento,
        quantidadeParcelas: pagamento.quantidadeParcelas,
        linhasMisto: pagamento.linhasMisto,
        planoFiado: valorFiado > 0.001 ? List.from(_planoFiadoParcelas) : null,
      );
      final entrega = DadosEntregaOrcamento(
        tipoEntrega: _resolverTipoEntregaVendaCarrinho(),
        valorFrete: valorFrete,
        enderecoEntrega: _enderecoEntregaController.text.trim(),
        observacaoEntrega: _observacaoEntregaController.text.trim(),
        prioridadeEntrega: _carrinhoTemItemCarreto
            ? _prioridadeEntregaSelecionada
            : 'normal',
        janelaEntrega: _carrinhoTemItemCarreto
            ? _janelaEntregaSelecionada
            : 'nao_definida',
        dataEntregaMarcada:
            _carrinhoTemItemCarreto ? _dataEntregaMarcada : null,
      );
      final orcamentoEdicaoId = _orcamentoEmEdicaoId;
      int orcamentoId;
      final descontoPdV = _valorDescontoReaisPdV();
      if (orcamentoEdicaoId != null) {
        widget.vendaRepository.atualizarOrcamento(
          orcamentoEdicaoId,
          itens,
          pagamento: pagamento,
          entrega: entrega,
          clienteId: _clienteSelecionadoId,
          vendedorId: _vendedorSelecionadoId,
          descontoEmReais: descontoPdV,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
        orcamentoId = orcamentoEdicaoId;
      } else {
        orcamentoId = widget.vendaRepository.registrarOrcamento(
          itens,
          pagamento: pagamento,
          entrega: entrega,
          clienteId: _clienteSelecionadoId,
          vendedorId: _vendedorSelecionadoId,
          descontoEmReais: descontoPdV,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      }
      await LanSyncScheduler.solicitarSyncImediato();
      if (!mounted) return;
      final vendaSalva = widget.vendaRepository.obterPorId(orcamentoId);
      final numeroOrcamentoSalvo =
          vendaSalva?.numeroOrcamento ?? _orcamentoEmEdicaoNumero;
      if (fechamentoDialogContext != null && fechamentoDialogContext.mounted) {
        Navigator.of(fechamentoDialogContext).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orcamentoEdicaoId != null
                ? 'Venda $numeroOrcamentoSalvo atualizada com sucesso.'
                : 'Orcamento $numeroOrcamentoSalvo salvo — informe este numero no caixa.',
          ),
        ),
      );
      if (vendaSalva != null && mounted) {
        await _mostrarAcoesPdfOrcamento(vendaSalva);
      }
      if (mounted) {
        _prepararNovaVendaAposEnvioCaixa(
          numeroOrcamentoSalvo: numeroOrcamentoSalvo,
          totalOrcamentoSalvo: vendaSalva?.total,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar venda: $e')));
    } finally {
      _salvandoOrcamento = false;
    }
  }

  Future<bool> _confirmarSubstituirRascunhoAtual() async {
    if (_carrinho.isEmpty) {
      return true;
    }
    final resposta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Carregar outro orcamento'),
        content: const Text(
          'Existe um orcamento em edicao na tela. Deseja descartar este rascunho e carregar outro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Carregar'),
          ),
        ],
      ),
    );
    return resposta == true;
  }

  String _rotuloVendedorUmLinhaOrcamento(Venda venda) {
    final vendedor = _vendedorDaVenda(venda);
    if (vendedor == null) {
      return 'Sem vendedor';
    }
    final nome = vendedor.apelido.trim().isNotEmpty
        ? vendedor.apelido.trim()
        : vendedor.nomeCompleto.trim();
    final codigo = vendedor.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  String _normalizarTextoComparacao(String texto) {
    var t = texto.trim().toLowerCase();
    const mapa = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };
    mapa.forEach((origem, destino) {
      t = t.replaceAll(origem, destino);
    });
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return t;
  }

  Produto? _resolverProdutoItemOrcamento(ItemVenda item) {
    final porTarget = item.produto.target;
    if (porTarget != null) {
      return porTarget;
    }
    final porId = widget.produtoRepository.obterPorId(item.produto.targetId);
    if (porId != null) {
      return porId;
    }

    final nomeItem = _normalizarTextoComparacao(item.nomeProduto);
    if (nomeItem.isEmpty) {
      return null;
    }

    final candidatos = widget.produtoRepository.pesquisar(
      item.nomeProduto,
      limite: 12,
      somenteAtivos: false,
      excluirProdutosInternos: false,
    );
    final exato = candidatos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome == nomeItem;
    }).firstOrNull;
    if (exato != null) {
      return exato;
    }

    return candidatos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome.contains(nomeItem) || nomeItem.contains(nome);
    }).firstOrNull;
  }

  Future<void> _abrirLeitorOrcamento() async {
    final podeSubstituir = await _confirmarSubstituirRascunhoAtual();
    if (!mounted || !podeSubstituir) {
      return;
    }
    final pendentes = widget.vendaRepository.listarOrcamentosPendentes();
    if (pendentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao ha orcamentos pendentes para leitura.'),
        ),
      );
      return;
    }

    final pesquisaController = TextEditingController();
    List<Venda> resultados = List<Venda>.from(pendentes);
    final selecionado = await showDialog<Venda>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ler orcamento'),
              content: AdaptiveDialogPane(
                desktopWidth: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pesquisaController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Numero, cliente, vendedor...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        final termo = value.trim().toLowerCase();
                        setDialogState(() {
                          resultados = pendentes.where((orc) {
                            final cliente =
                                _clienteDaVenda(orc)?.nomeRazao ?? '';
                            final vendedor = _rotuloVendedorUmLinhaOrcamento(
                              orc,
                            );
                            return orc.numeroOrcamento.toString().contains(
                                  termo,
                                ) ||
                                cliente.toLowerCase().contains(termo) ||
                                vendedor.toLowerCase().contains(termo);
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: context.isCompactLayout ? 120 : 220,
                        maxHeight: adaptiveDialogListMaxHeight(context),
                      ),
                      child: resultados.isEmpty
                          ? const Center(
                              child: Text('Nenhum orcamento encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              itemBuilder: (context, index) {
                                final orc = resultados[index];
                                final cliente =
                                    _clienteDaVenda(orc)?.nomeRazao ??
                                    'Sem cliente';
                                return ListTile(
                                  title: Text(
                                    'Orcamento ${orc.numeroOrcamento}',
                                  ),
                                  subtitle: Text(
                                    '$cliente | Itens: ${orc.itens.length} | Total: ${_formatarMoeda(orc.total)}',
                                  ),
                                  onTap: () => Navigator.pop(context, orc),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaController.dispose();
    if (!mounted || selecionado == null) {
      return;
    }

    final orcamentoCompleto =
        widget.vendaRepository.obterPorId(selecionado.id) ?? selecionado;
    _aplicarOrcamentoParaEdicao(orcamentoCompleto);
  }

  bool _aplicarOrcamentoParaEdicao(Venda selecionado) {
    final orcamentoCompleto =
        widget.vendaRepository.obterPorId(selecionado.id) ?? selecionado;
    final drafts = <_OrcamentoItemDraft>[];
    final nomesItensSemProduto = <String>[];
    for (final item in orcamentoCompleto.itens) {
      final produto = _resolverProdutoItemOrcamento(item);
      if (produto == null) {
        nomesItensSemProduto.add(item.nomeProduto);
        continue;
      }
      var tipoItem = EntregaVendaHelper.normalizarTipoItem(item.tipoEntregaItem);
      if (tipoItem == EntregaVendaHelper.tipoRetirada &&
          orcamentoCompleto.tipoEntrega != EntregaVendaHelper.tipoRetirada &&
          orcamentoCompleto.tipoEntrega != EntregaVendaHelper.tipoMisto) {
        tipoItem = EntregaVendaHelper.normalizarTipoItem(
          orcamentoCompleto.tipoEntrega,
        );
      }
      drafts.add(
        _OrcamentoItemDraft(
          produto: produto,
          quantidade: item.quantidade,
          precoTipo: item.precoTipo,
          precoUnitario: item.precoUnitario,
          tipoEntregaItem: tipoItem,
          promocaoId: item.promocaoId,
          promocaoNome: item.promocaoNomeSnapshot,
        ),
      );
    }
    if (drafts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nomesItensSemProduto.isNotEmpty
                  ? 'Nao foi possivel carregar itens do orcamento. Produtos sem cadastro atual.'
                  : 'Nao foi possivel carregar itens do orcamento selecionado.',
            ),
          ),
        );
      }
      return false;
    }

    final clienteIdCarregado = orcamentoCompleto.cliente.targetId == 0
        ? null
        : orcamentoCompleto.cliente.targetId;
    final vendedorIdCarregado = orcamentoCompleto.vendedor.targetId == 0
        ? null
        : orcamentoCompleto.vendedor.targetId;
    final clienteCarregado = clienteIdCarregado == null
        ? null
        : widget.clienteRepository.obterPorId(clienteIdCarregado);
    final clienteIdValido =
        clienteCarregado != null && clienteCarregado.ativo
        ? clienteIdCarregado
        : null;
    final vendedorIdValido =
        vendedorIdCarregado != null &&
            _vendedoresAtivos.any((v) => v.id == vendedorIdCarregado)
        ? vendedorIdCarregado
        : null;
    final tipoEntregaValido = switch (orcamentoCompleto.tipoEntrega) {
      'entrega_loja' => EntregaVendaHelper.tipoEntregaLoja,
      'retirada_futura' => EntregaVendaHelper.tipoRetiradaFutura,
      'misto' => EntregaVendaHelper.tipoRetirada,
      _ => EntregaVendaHelper.tipoRetirada,
    };
    final prioridadeValida = switch (orcamentoCompleto.prioridadeEntrega) {
      'urgente' => 'urgente',
      'agendada' => 'agendada',
      _ => 'normal',
    };
    final janelaValida = switch (orcamentoCompleto.janelaEntrega) {
      'manha' => 'manha',
      'tarde' => 'tarde',
      _ => 'nao_definida',
    };
    var indiceEndereco = 0;
    if (clienteIdValido != null) {
      final cliente = widget.clienteRepository.obterPorId(clienteIdValido);
      final enderecos = cliente?.listarEnderecos() ?? const <EnderecoCliente>[];
      if (enderecos.isNotEmpty) {
        final enderecoAtual = orcamentoCompleto.enderecoEntrega.trim();
        final encontrado = enderecos.indexWhere(
          (e) => e.resumo().trim() == enderecoAtual,
        );
        if (encontrado >= 0) {
          indiceEndereco = encontrado;
        }
      }
    }

    setState(() {
      _carrinho
        ..clear()
        ..addAll(drafts);
      _indiceLinhaCarrinho = _carrinho.isEmpty ? null : 0;
      _clienteSelecionadoId = clienteIdValido;
      _indiceEnderecoSelecionado = indiceEndereco;
      _vendedorSelecionadoId = vendedorIdValido;
      _disposeLinhasPagamentoMisto();
      if (orcamentoCompleto.formaPagamento == 'misto' &&
          orcamentoCompleto.pagamentosJson.trim().isNotEmpty) {
        _pagamentoMistoPdV = true;
        for (final ln in PagamentoOrcamentoCodec.decode(
          orcamentoCompleto.pagamentosJson,
        )) {
          _linhasPagamentoMisto.add(
            _LinhaPagamentoMistoPdV(
              meio: ln.meio,
              valorController: TextEditingController(
                text: ln.valor > 0
                    ? ln.valor.toStringAsFixed(2).replaceAll('.', ',')
                    : '',
              ),
              parcelas: ln.parcelas <= 0 ? 1 : ln.parcelas,
            ),
          );
        }
        _formaPagamentoSelecionada = 'dinheiro';
        _parcelasSelecionadas = 1;
      } else {
        _pagamentoMistoPdV = false;
        _formaPagamentoSelecionada = orcamentoCompleto.formaPagamento;
        _parcelasSelecionadas = orcamentoCompleto.quantidadeParcelas <= 0
            ? 1
            : orcamentoCompleto.quantidadeParcelas;
      }
      _planoFiadoParcelas =
          PlanoFiadoCodec.decode(orcamentoCompleto.planoFiadoJson);
      _tipoEntregaSelecionada = tipoEntregaValido;
      _prioridadeEntregaSelecionada = prioridadeValida;
      _janelaEntregaSelecionada = janelaValida;
      _dataEntregaMarcada = orcamentoCompleto.dataEntregaMarcada;
      _valorFreteController.text = orcamentoCompleto.valorFrete
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _enderecoEntregaController.text = orcamentoCompleto.enderecoEntrega;
      _observacaoEntregaController.text = orcamentoCompleto.observacaoEntrega;
      _orcamentoEmEdicaoId = orcamentoCompleto.id;
      _orcamentoEmEdicaoNumero = orcamentoCompleto.numeroOrcamento;
    });
    _sincronizarTextoBuscaClientePdv();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nomesItensSemProduto.isEmpty
                ? 'Orcamento ${orcamentoCompleto.numeroOrcamento} carregado com ${drafts.length} item(ns) para edicao.'
                : 'Orcamento ${orcamentoCompleto.numeroOrcamento} carregado com ${drafts.length} item(ns). ${nomesItensSemProduto.length} item(ns) sem produto cadastrado foram ignorados.',
          ),
        ),
      );
    }
    return true;
  }

  String _rotuloFormaPagamento(String forma) {
    switch (forma) {
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartao de credito';
      case 'cartao_debito':
        return 'Cartao de debito';
      case 'fiado':
        return 'Fiado';
      case 'transferencia':
        return 'Transferencia';
      case 'misto':
        return 'Pagamento misto';
      case 'dinheiro':
        return 'Dinheiro';
      default:
        if (forma.startsWith('cartao')) return forma;
        return forma.isEmpty ? '-' : forma;
    }
  }

  String _textoPagamentoOrcamentoPdf(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${_rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' | ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    return linhas.map((l) {
      final base =
          '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}';
      if (l.meio == 'cartao_credito' && l.parcelas > 0) {
        final vp = l.valor / l.parcelas;
        return '$base ${l.parcelas}x de ${_formatarMoeda(vp)}';
      }
      return base;
    }).join('; ');
  }

  Cliente? _clienteDaVenda(Venda venda) {
    final clienteLigado = venda.cliente.target;
    if (clienteLigado != null) {
      return clienteLigado;
    }
    final clienteId = venda.cliente.targetId;
    if (clienteId == 0) {
      return null;
    }
    return widget.clienteRepository.obterPorId(clienteId);
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    final ligado = venda.vendedor.target;
    if (ligado != null) {
      return ligado;
    }
    final vid = venda.vendedor.targetId;
    if (vid == 0) {
      return null;
    }
    return widget.vendedorRepository.obterPorId(vid);
  }

  String _rotuloVendedorOrcamentoPdf(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) {
      return 'Sem vendedor';
    }
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isNotEmpty ? '$codigo · $nome' : nome;
  }

  Future<CupomPdfGerado> _gerarOrcamentoPdfBytes(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    final empresa = await widget.appConfigRepository.carregarEmpresaConfig();
    final logoBytes = empresa.logoPath.trim().isNotEmpty
        ? await File(
            empresa.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final dataEmissao = DateTime.now();
    final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(dataEmissao);
    final validade = dataEmissao.add(Duration(days: _validadeOrcamentoDias));
    final validadeFmt = DateFormat('dd/MM/yyyy').format(validade);
    final descontoOrcamento = venda.descontoImplicitoTotal;
    final temFrete = venda.valorFrete > 0;
    final temCliente = cliente != null && cliente.nomeRazao.trim().isNotEmpty;
    final temVendedor = _vendedorDaVenda(venda) != null;
    final modelo = empresaModeloPdfDeString(empresa.modeloPdf);
    final comLogo = logoBytes.isNotEmpty;
    final layout = empresa.layoutImpressao.orcamento.copyWith(
      familiaFonte: LayoutFamiliaFonte.courier,
    );
    final doc = CupomPdfLayout.criarDocumento(layout);
    final linhasTexto = CupomPdfLayout.contarLinhasCabecalhoOrcamento(
      layout: layout,
      temCliente: temCliente,
      temVendedor: temVendedor,
      cliente: cliente,
    );
    final linhasExtras = CupomPdfLayout.contarLinhasExtrasOrcamento(
      layout: layout,
      temDesconto: descontoOrcamento > 0,
      temFrete: temFrete,
      textoRodape: empresa.rodapeOrcamento,
    ) +
        PlanoFiadoCodec.contarLinhasPdf(venda);
    final unidadesItens = CupomPdfLayout.unidadesAlturaItensTermico(
      venda.itens.map((i) => i.nomeProduto),
    );

    final pageFormat = CupomPdfLayout.formatoPagina(
      modelo,
      layout: layout,
      linhasTexto: linhasTexto,
      qtdItens: unidadesItens > 0 ? unidadesItens : venda.itens.length,
      linhasExtras: linhasExtras,
      comLogo: comLogo,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              ...CupomPdfLayout.cabecalhoEmpresa(
                layout: layout,
                nomeLoja: empresa.nomeLoja,
                logoBytes: comLogo ? logoBytes : null,
                telefone: empresa.telefone,
                endereco: empresa.endereco,
              ),
              CupomPdfLayout.faixaTipoDocumento(
                layout: layout,
                titulo: layout.tituloDocumentoEfetivoOrcamento,
              ),
              CupomPdfLayout.textoCorpo(
                'Numero: ${venda.numeroOrcamento}',
                layout,
              ),
              CupomPdfLayout.textoCorpo('Data: $dataHora', layout),
              if (temCliente) ...[
                CupomPdfLayout.textoCorpo(
                  'Cliente: ${cliente.nomeRazao}',
                  layout,
                ),
                if (layout.exibirDocumentoCliente &&
                    cliente.documento.trim().isNotEmpty)
                  CupomPdfLayout.textoCorpo(
                    'Documento: ${cliente.documento}',
                    layout,
                  ),
                if (layout.exibirTelefoneCliente &&
                    cliente.telefone.trim().isNotEmpty)
                  CupomPdfLayout.textoCorpo(
                    'Telefone: ${cliente.telefone}',
                    layout,
                  ),
              ],
              if (temVendedor && layout.exibirVendedor)
                CupomPdfLayout.textoCorpo(
                  'Vendedor: ${_rotuloVendedorOrcamentoPdf(venda)}',
                  layout,
                ),
              if (layout.exibirValidadeOrcamento)
                CupomPdfLayout.textoCorpo(
                  layout.espacoCompacto
                      ? 'Valido ate $validadeFmt'
                      : 'Validade do orcamento: $validadeFmt ($_validadeOrcamentoDias dias)',
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('ITENS', layout),
              if (CupomPdfLayout.cabecalhoColunasItens(layout) != null)
                CupomPdfLayout.cabecalhoColunasItens(layout)!,
              ...venda.itens.map(
                (item) {
                  final fracionada =
                      item.produto.target?.permiteQuantidadeFracionada ??
                          false;
                  return CupomPdfLayout.itemVenda(
                    layout: layout,
                    nomeProduto: ProdutoNomeExibicao.paraImpressaoItem(item),
                    quantidade: item.quantidade,
                    quantidadeExibicao: QuantidadeVendaUtil.formatarExibicao(
                      item.quantidadeVendaEfetiva,
                      fracionada: fracionada,
                    ),
                    precoUnitario: item.precoUnitario,
                    subtotal: item.subtotal,
                    formatarMoeda: _formatarMoeda,
                  );
                },
              ),
              if (layout.divisoriaDestaqueAntesTotais)
                CupomPdfLayout.divisoriaSecao(layout: layout, destaque: true),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Subtotal produtos:',
                valor: _formatarMoeda(venda.somaSubtotalItens),
              ),
              if (temFrete)
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Frete:',
                  valor: _formatarMoeda(venda.valorFrete),
                ),
              if (descontoOrcamento > 0)
                CupomPdfLayout.linhaTotal(
                  layout: layout,
                  rotulo: 'Desconto:',
                  valor: '- ${_formatarMoeda(descontoOrcamento)}',
                ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Total:',
                valor: _formatarMoeda(venda.total),
                destaque: layout.destacarTotal,
              ),
              CupomPdfLayout.linhaTotal(
                layout: layout,
                rotulo: 'Pagamento:',
                valor: _textoPagamentoOrcamentoPdf(venda),
                colunas: layout.alinharPagamentoColunas,
              ),
              if (PlanoFiadoCodec.vendaTemPlanoQuitacao(venda)) ...[
                CupomPdfLayout.textoCorpo(
                  'Condicao de quitacao (fiado):',
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
                ...PlanoFiadoCodec.linhasTextoPdf(venda).map(
                  (linha) => CupomPdfLayout.textoCorpo(linha, layout),
                ),
              ],
              if (!layout.espacoCompacto)
                CupomPdfLayout.textoCorpo(
                  'Este orcamento e valido por $_validadeOrcamentoDias dias a partir da data de emissao.',
                  layout,
                  fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
                ),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: empresa.rodapeOrcamento,
              ),
              CupomPdfLayout.espacoFinalDocumento(layout),
            ],
          );
        },
      ),
    );
    return CupomPdfGerado(
      bytes: await doc.save(),
      pageFormat: pageFormat,
      layout: layout,
    );
  }

  Future<String?> _escolherSalvarPdf({
    required Uint8List bytes,
    required String suggestedFileName,
    String? initialDirectory,
  }) async {
    final selectedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Escolha onde salvar o PDF',
      fileName: suggestedFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (selectedPath == null) return null;
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  KeyEventResult _atalhoDialogoOrcamentoSalvo(
    FocusNode node,
    KeyEvent event,
    void Function(String acao) fechar,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      fechar('fechar');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      fechar('pdf');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      fechar('direto');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      fechar('imprimir');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      fechar('imprimir');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f10) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _mostrarAcoesPdfOrcamento(Venda venda) async {
    final numOrcamento =
        venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    _dialogoOrcamentoSalvoAberto = true;
    String? acao;
    try {
      acao = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        void fechar(String valor) {
          if (!dialogContext.mounted) return;
          Navigator.pop(dialogContext, valor);
        }

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) =>
              _atalhoDialogoOrcamentoSalvo(node, event, fechar),
          child: AlertDialog(
            title: const Text('Orcamento salvo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Numero para o cliente informar no caixa:',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    child: Text(
                      '$numOrcamento',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Anote no papel ou envie ao cliente. No caixa, informe este numero para pagar.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                const Text('Deseja imprimir o orcamento ou mandar em PDF?'),
                const SizedBox(height: 10),
                const Text(
                  'Teclado: Esc ou 1 — fechar · 2 — PDF · 3 — impressao direta · '
                  '4 ou Enter — imprimir · F10 ignorado nesta tela',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'fechar'),
                child: const Text('Fechar (Esc · 1)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Mandar em PDF (2)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'direto'),
                icon: const Icon(Icons.print),
                label: const Text('Impressao direta (3)'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'imprimir'),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir (4 · Enter)'),
              ),
            ],
          ),
        );
      },
    );
    } finally {
      _dialogoOrcamentoSalvoAberto = false;
    }
    if (!mounted || acao == null || acao == 'fechar') return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      final pdf = await _gerarOrcamentoPdfBytes(venda);
      if (!mounted) return;
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdf.bytes);
        return;
      }
      if (acao == 'direto') {
        final printer =
            await widget.printService.resolverImpressoraPorNome(config.impressoraPadrao);
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impressora padrao nao configurada/encontrada.'),
            ),
          );
          return;
        }
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdf.bytes,
          name: 'Orcamento ${venda.numeroOrcamento}',
          format: config.modeloPdf == 'a4'
              ? PdfPageFormat.a4
              : CupomPdfLayout.formatoImpressaoDireta(
                  layout: pdf.layout,
                  formatoPdf: pdf.pageFormat,
                ),
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdf.bytes,
        suggestedFileName: 'orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e, st) {
      debugPrint('Erro ao gerar/imprimir orcamento: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nao foi possivel gerar/imprimir orcamento: $e'),
        ),
      );
    }
  }

  double get _totalOrcamento =>
      _carrinho.fold(0, (total, item) => total + item.subtotal);

  double get _valorFreteAtual => _carrinhoTemItemCarreto
      ? _parseValorMonetario(_valorFreteController.text)
      : 0.0;

  double get _totalGeralComFrete => _totalOrcamento + _valorFreteAtual;

  /// Subtotal de linhas sem promocao (desconto PDV nao incide em promo).
  double get _subtotalElegivelDescontoPdV => _carrinho
      .where((i) => i.promocaoId <= 0)
      .fold(0.0, (s, i) => s + i.subtotal);

  List<LinhaCalculoLimiteDescontoPdv> get _linhasLimiteDescontoPdV =>
      _carrinho
          .map(
            (i) => LinhaCalculoLimiteDescontoPdv(
              produto: i.produto,
              precoTipo: i.precoTipo,
              subtotal: i.subtotal,
              promocaoId: i.promocaoId,
            ),
          )
          .toList();

  double _percentualMaximoEfetivoDescontoPdV() =>
      ProdutoLimiteDescontoPdv.percentualEquivalenteSobreSubtotal(
        linhas: _linhasLimiteDescontoPdV,
        tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
      );

  /// Valor maximo de desconto em reais (teto por produto/tabela + config).
  double _valorMaximoDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    return ProdutoLimiteDescontoPdv.valorMaximoDescontoReais(
      linhas: _linhasLimiteDescontoPdV,
      tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
    );
  }

  double _percentualDigitadoPdV() {
    if (_tipoDescontoPdV != 'percentual') return 0;
    final bruto = _percentualDigitadoBrutoSemLimitePdV();
    if (bruto == null) return 0;
    return bruto.clamp(0.0, _percentualMaximoEfetivoDescontoPdV());
  }

  /// Percentual digitado sem aplicar o teto (para aviso quando ultrapassa).
  double? _percentualDigitadoBrutoSemLimitePdV() {
    if (_tipoDescontoPdV != 'percentual') return null;
    final raw = _descontoPdVController.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    if (v == null || v.isNaN) return null;
    return v;
  }

  bool _descontoPdVDigitadoUltrapassaTeto() {
    if (_maxDescontoPercentualPdv <= 0) return false;
    final maxPct = _percentualMaximoEfetivoDescontoPdV();
    final maxReais = _valorMaximoDescontoReaisPdV();
    const eps = 1e-6;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV();
      if (bruto == null) return false;
      return bruto > maxPct + eps;
    }
    if (_descontoPdVController.text.trim().isEmpty) return false;
    final brutoReais = _parseValorMonetario(_descontoPdVController.text);
    return brutoReais > maxReais + eps;
  }

  bool _descontoPdVUltrapassaTetoSemAutorizacao() {
    return _descontoPdVDigitadoUltrapassaTeto() &&
        !_descontoAcimaTetoAutorizadoPdv;
  }

  double _descontoSolicitadoReaisBrutoPdV() {
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0) return 0;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV();
      if (bruto == null) return 0;
      return (sub * bruto / 100).clamp(0.0, sub);
    }
    return _parseValorMonetario(_descontoPdVController.text).clamp(0.0, sub);
  }

  Future<bool> _solicitarAutorizacaoDescontoAcimaTetoPdV() async {
    if (!_descontoPdVDigitadoUltrapassaTeto()) {
      _descontoAcimaTetoAutorizadoPdv = false;
      _descontoAutorizadoPorPdV = null;
      return true;
    }
    if (_descontoAcimaTetoAutorizadoPdv) return true;

    final autorizadoPor = await solicitarAutorizacaoDescontoAcimaTetoPdv(
      context,
      _usuarioRepository,
      usuarioLogado: widget.usuarioLogado,
      maximoPermitidoReais: _valorMaximoDescontoReaisPdV(),
      descontoSolicitadoReais: _descontoSolicitadoReaisBrutoPdV(),
      formatarMoeda: _formatarMoeda,
    );
    if (autorizadoPor == null) return false;
    _descontoAcimaTetoAutorizadoPdv = true;
    _descontoAutorizadoPorPdV = autorizadoPor;
    return true;
  }

  void _resetarAutorizacaoDescontoAcimaTetoPdV() {
    _descontoAcimaTetoAutorizadoPdv = false;
    _descontoAutorizadoPorPdV = null;
  }

  String _mensagemErroDescontoPdVUltrapassaTeto() {
    final maxPct = _percentualMaximoEfetivoDescontoPdV();
    final maxReais = _valorMaximoDescontoReaisPdV();
    return 'Acima do permitido. Maximo: ${maxPct.toStringAsFixed(1)}% '
        'do subtotal = ${_formatarMoeda(maxReais)}.';
  }

  /// Desconto apenas sobre o subtotal; frete entra inteiro no total a pagar.
  double _valorDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0) return 0;
    final maxReais = _valorMaximoDescontoReaisPdV();
    final acimaAutorizado = _descontoAcimaTetoAutorizadoPdv;
    if (_tipoDescontoPdV == 'percentual') {
      final bruto = _percentualDigitadoBrutoSemLimitePdV() ?? 0;
      final pct = acimaAutorizado
          ? bruto.clamp(0.0, 100.0)
          : bruto.clamp(0.0, _percentualMaximoEfetivoDescontoPdV());
      final valor = sub * pct / 100;
      return acimaAutorizado
          ? valor.clamp(0.0, sub)
          : valor.clamp(0.0, maxReais);
    }
    final digitado = _parseValorMonetario(_descontoPdVController.text);
    if (acimaAutorizado) return digitado.clamp(0.0, sub);
    return digitado.clamp(0.0, maxReais).clamp(0.0, sub);
  }

  double _percentualEfetivoSobreSubtotalPdV() {
    final sub = _subtotalElegivelDescontoPdV;
    if (sub <= 0.004) return 0;
    return _valorDescontoReaisPdV() / sub * 100;
  }

  double _totalLiquidoPagamentoPdV() =>
      (_totalGeralComFrete - _valorDescontoReaisPdV()).clamp(
        0.0,
        double.infinity,
      );

  double _valorFiadoCheckoutPdV() {
    final total = _totalLiquidoPagamentoPdV();
    if (_pagamentoMistoPdV) {
      try {
        final linhas = _montarLinhasMistoParaSalvar(total);
        if (linhas == null) return 0;
        return PagamentoOrcamentoCodec.somaPorMeio(linhas, 'fiado');
      } on StateError {
        return 0;
      }
    }
    if (_formaPagamentoSelecionada == 'fiado') return total;
    return 0;
  }

  bool _precisaPlanoFiadoPdV() => _valorFiadoCheckoutPdV() > 0.001;

  String _rotuloParcelaCreditoValor(int parcelas, double valorBase) {
    final n = parcelas <= 0 ? 1 : parcelas;
    if (valorBase <= 0.001) {
      return '${n}x';
    }
    final valorParcela = valorBase / n;
    return '${n}x · ${_formatarMoeda(valorParcela)}';
  }

  String _rotuloParcela(int parcelas) =>
      _rotuloParcelaCreditoValor(parcelas, _totalLiquidoPagamentoPdV());

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): SelecionarPrecoListaIntent(
          'preco1',
        ),
        SingleActivator(LogicalKeyboardKey.f2): SelecionarPrecoListaIntent(
          'preco2',
        ),
        SingleActivator(LogicalKeyboardKey.f3): SelecionarPrecoListaIntent(
          'preco3',
        ),
        SingleActivator(LogicalKeyboardKey.f1, control: true):
            SelecionarEntregaPadraoIntent('retirada'),
        SingleActivator(LogicalKeyboardKey.f2, control: true):
            SelecionarEntregaPadraoIntent('retirada_futura'),
        SingleActivator(LogicalKeyboardKey.f3, control: true):
            SelecionarEntregaPadraoIntent('entrega_loja'),
        SingleActivator(LogicalKeyboardKey.f4): PdvAbrirConsultaIntent(),
        SingleActivator(LogicalKeyboardKey.f5): PdvRecarregarProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f6): PdvFocarCarrinhoIntent(),
        SingleActivator(LogicalKeyboardKey.f8):
            PdvFocarPesquisaProdutosIntent(),
        SingleActivator(LogicalKeyboardKey.f10): PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.f11): PdvToggleCalculadoraIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            PdvSalvarOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyO, control: true):
            PdvLerOrcamentoIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            PdvLimparPesquisaIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SelecionarPrecoListaIntent:
              CallbackAction<SelecionarPrecoListaIntent>(
                onInvoke: (intent) {
                  _definirTabelaPrecoPdv(intent.precoTipo);
                  return null;
                },
              ),
          SelecionarEntregaPadraoIntent:
              CallbackAction<SelecionarEntregaPadraoIntent>(
                onInvoke: (intent) {
                  _definirEntregaPadraoPdv(intent.tipoEntrega);
                  return null;
                },
              ),
          PdvAbrirConsultaIntent: CallbackAction<PdvAbrirConsultaIntent>(
            onInvoke: (_) {
              unawaited(_abrirConsultaProdutos());
              return null;
            },
          ),
          PdvRecarregarProdutosIntent:
              CallbackAction<PdvRecarregarProdutosIntent>(
                onInvoke: (_) {
                  _carregarDadosIniciais();
                  return null;
                },
              ),
          PdvFocarCarrinhoIntent: CallbackAction<PdvFocarCarrinhoIntent>(
            onInvoke: (_) {
              _focarCarrinhoAtalho();
              return null;
            },
          ),
          PdvFocarPesquisaProdutosIntent:
              CallbackAction<PdvFocarPesquisaProdutosIntent>(
                onInvoke: (_) {
                  _atalhoF8Pdv();
                  return null;
                },
              ),
          PdvSalvarOrcamentoIntent: CallbackAction<PdvSalvarOrcamentoIntent>(
            onInvoke: (_) {
              if (_dialogoOrcamentoSalvoAberto ||
                  _checkoutDialogAberto ||
                  _salvandoOrcamento) {
                return null;
              }
              unawaited(_abrirPassoFechamentoVenda());
              return null;
            },
          ),
          PdvLerOrcamentoIntent: CallbackAction<PdvLerOrcamentoIntent>(
            onInvoke: (_) {
              unawaited(_abrirLeitorOrcamento());
              return null;
            },
          ),
          PdvLimparPesquisaIntent: CallbackAction<PdvLimparPesquisaIntent>(
            onInvoke: (_) {
              _limparPesquisaAtalho();
              return null;
            },
          ),
          PdvToggleCalculadoraIntent:
              CallbackAction<PdvToggleCalculadoraIntent>(
            onInvoke: (_) {
              _toggleCalculadoraPdv();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text(
                    'Ponto de Venda',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _buildSeletorVendedorAppBarPdv(),
                const SizedBox(width: 4),
                _buildSeletorPrecoListaAppBarPdv(),
                const SizedBox(width: 4),
                _buildSeletorEntregaPadraoAppBarPdv(),
                const SizedBox(width: 4),
                _buildSeletorClienteAppBarPdv(),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Calculadora (F11)',
                onPressed: _toggleCalculadoraPdv,
                icon: const Icon(Icons.calculate_outlined),
              ),
              IconButton(
                tooltip: 'Consultar produtos (F4)',
                onPressed: () => unawaited(_abrirConsultaProdutos()),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Ler orcamento para editar',
                onPressed: _abrirLeitorOrcamento,
                icon: const Icon(Icons.description_outlined),
              ),
              IconButton(
                tooltip: 'Inserir kit de orcamento',
                onPressed: _inserirKitNoOrcamento,
                icon: const Icon(Icons.widgets_outlined),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.intentTrocaComNota != null && _trocaComNotaBannerVisivel)
                  TrocaComNotaPdvBanner(
                    intent: widget.intentTrocaComNota!,
                    creditoAplicadoNoDesconto: _trocaComNotaCreditoAplicadoReais,
                    maxDescontoPermitidoReais: _valorMaximoDescontoReaisPdV(),
                    onFechar: () {
                      setState(() => _trocaComNotaBannerVisivel = false);
                    },
                  ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(5),
                  child: _PdvHeaderPesquisa(
                    modoBarraCarrinho: true,
                    pesquisaFocus: _pesquisaFocus,
                    pesquisaController: _pesquisaController,
                    mostrarAjudaAtalhos: _mostrarAjudaAtalhos,
                    onLimparBusca: _limparPesquisaAtalho,
                    onAbrirConsulta: () => unawaited(_abrirConsultaProdutos()),
                    onSubmitEntrada: () =>
                        unawaited(_processarEntradaPesquisaPdv()),
                    onRecarregarProdutos: _carregarDadosIniciais,
                    onToggleAjudaAtalhos: () {
                      setState(() {
                        _mostrarAjudaAtalhos = !_mostrarAjudaAtalhos;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildAreaCarrinhoComPreviewPdv(),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Barra de pesquisa no topo do carrinho (Enter abre consulta em tela cheia).
class _PdvHeaderPesquisa extends StatelessWidget {
  const _PdvHeaderPesquisa({
    required this.modoBarraCarrinho,
    required this.pesquisaFocus,
    required this.pesquisaController,
    required this.mostrarAjudaAtalhos,
    required this.onLimparBusca,
    required this.onAbrirConsulta,
    required this.onSubmitEntrada,
    required this.onRecarregarProdutos,
    required this.onToggleAjudaAtalhos,
  });

  final bool modoBarraCarrinho;
  final FocusNode pesquisaFocus;
  final TextEditingController pesquisaController;
  final bool mostrarAjudaAtalhos;
  final VoidCallback onLimparBusca;
  final VoidCallback onAbrirConsulta;
  final VoidCallback onSubmitEntrada;
  final VoidCallback onRecarregarProdutos;
  final VoidCallback onToggleAjudaAtalhos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, modoBarraCarrinho ? 6 : 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: false,
              focusNode: pesquisaFocus,
              controller: pesquisaController,
              textInputAction: TextInputAction.search,
              style: modoBarraCarrinho
                  ? Theme.of(context).textTheme.bodyMedium
                  : null,
              decoration: InputDecoration(
                isDense: modoBarraCarrinho,
                filled: true,
                fillColor: scheme.surface.withValues(alpha: 0.92),
                contentPadding: modoBarraCarrinho
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                    : null,
                hintText: modoBarraCarrinho
                    ? 'Pesquisar produto · Leitor EAN · Enter/F4 consulta'
                    : null,
                labelText: modoBarraCarrinho
                    ? null
                    : 'Pesquisar produto para venda',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Limpar busca',
                      visualDensity: VisualDensity.compact,
                      onPressed: onLimparBusca,
                      icon: const Icon(Icons.clear, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Abrir consulta de produtos (F4)',
                      visualDensity: VisualDensity.compact,
                      onPressed: onAbrirConsulta,
                      icon: const Icon(Icons.search, size: 20),
                    ),
                    if (!modoBarraCarrinho)
                      IconButton(
                        tooltip: 'Recarregar cadastros',
                        onPressed: onRecarregarProdutos,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
              onSubmitted: (_) => onSubmitEntrada(),
            ),
            if (!modoBarraCarrinho) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onToggleAjudaAtalhos,
                  icon: Icon(
                    mostrarAjudaAtalhos
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  label: Text(
                    mostrarAjudaAtalhos
                        ? 'Ocultar atalhos'
                        : 'Ajuda de atalhos',
                  ),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onToggleAjudaAtalhos,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    mostrarAjudaAtalhos ? 'Ocultar atalhos' : 'Atalhos',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            AnimatedCrossFade(
              crossFadeState: mostrarAjudaAtalhos
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 180),
              firstChild: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: const PdvAtalhosAjudaPesquisa(),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista compacta do carrinho do PDV (foco F6, setas, exclusão).
class _PdvCarrinhoProdutos extends StatefulWidget {
  const _PdvCarrinhoProdutos({
    required this.carrinhoFocus,
    required this.onKeyCarrinho,
    required this.itens,
    required this.indiceLinhaSelecionada,
    required this.onSelecionarLinha,
    required this.rotuloPreco,
    required this.formatarMoeda,
    required this.onAlterarQuantidade,
    required this.onRemoverItem,
    required this.onAlternarTipoEntrega,
    required this.onDividirLinha,
    required this.onAlterarPrecoLinha,
    required this.onIrPesquisaQuandoVazio,
    required this.produtoExcedeEstoque,
  });

  final FocusNode carrinhoFocus;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyCarrinho;
  final List<_OrcamentoItemDraft> itens;
  final int? indiceLinhaSelecionada;
  final void Function(int index) onSelecionarLinha;
  final String Function(String) rotuloPreco;
  final String Function(double) formatarMoeda;
  final void Function(int index, int delta) onAlterarQuantidade;
  final void Function(int index) onRemoverItem;
  final void Function(int index) onAlternarTipoEntrega;
  final Future<void> Function(int index) onDividirLinha;
  final Future<void> Function(int index) onAlterarPrecoLinha;
  final VoidCallback onIrPesquisaQuandoVazio;
  final bool Function(Produto produto) produtoExcedeEstoque;

  @override
  State<_PdvCarrinhoProdutos> createState() => _PdvCarrinhoProdutosState();
}

class _PdvCarrinhoProdutosState extends State<_PdvCarrinhoProdutos> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PdvCarrinhoProdutos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indiceLinhaSelecionada != oldWidget.indiceLinhaSelecionada) {
      _rolarParaIndice(widget.indiceLinhaSelecionada);
    }
  }

  void _rolarParaIndice(int? indice) {
    if (indice == null || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final alvo = (indice * PdvCarrinhoLinhaCompacta.alturaLinha).clamp(0.0, max);
    _scrollController.jumpTo(alvo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (widget.itens.isEmpty) {
      return Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 44,
                  color: scheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhum item na venda.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onIrPesquisaQuandoVazio,
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar produto para venda'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Atalho: F8 ou F4',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Focus(
      focusNode: widget.carrinhoFocus,
      onKeyEvent: widget.onKeyCarrinho,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        itemExtent: PdvCarrinhoLinhaCompacta.alturaLinha,
        itemCount: widget.itens.length,
        itemBuilder: (context, index) {
          final item = widget.itens[index];
          final selecionado = widget.indiceLinhaSelecionada == index;
          return Semantics(
            container: true,
            label:
                '${item.produto.nome}, ${widget.rotuloPreco(item.precoTipo)}, quantidade ${item.quantidade}',
            child: PdvCarrinhoLinhaCompacta(
              nomeProduto: item.produto.nome,
              emPromocao: item.promocaoId > 0,
              estoqueInsuficiente: widget.produtoExcedeEstoque(item.produto),
              precoManual: item.precoUnitarioManual,
              rotuloPreco: widget.rotuloPreco(item.precoTipo),
              precoUnitarioFormatado: widget.formatarMoeda(item.precoUnitario),
              subtotalFormatado: widget.formatarMoeda(item.subtotal),
              quantidade: item.quantidade,
              rotuloUnidade: rotuloUnidadeProdutoLista(item.produto),
              detalheQuantidade: item.quantidadeEmUnidadeCompra
                  ? item.rotuloQuantidadeCarrinho
                  : null,
              tipoEntregaItem: item.tipoEntregaItem,
              selecionado: selecionado,
              linhaImpar: index.isOdd,
              onTap: () => widget.onSelecionarLinha(index),
              onAlternarTipoEntrega: () => widget.onAlternarTipoEntrega(index),
              onDiminuir: () => widget.onAlterarQuantidade(index, -1),
              onAumentar: () => widget.onAlterarQuantidade(index, 1),
              onDividir: () => widget.onDividirLinha(index),
              onAlterarPreco: () => widget.onAlterarPrecoLinha(index),
              onRemover: () => widget.onRemoverItem(index),
            ),
          );
        },
      ),
    );
  }
}

/// Painel lateral de checkout (colapsável, carrinho, totais na base, continuar).
class _PdvPainelCheckout extends StatelessWidget {
  const _PdvPainelCheckout({
    required this.leiauteEmpilhado,
    required this.keyPainel,
    required this.painelCheckoutRecolhido,
    required this.carrinhoCount,
    required this.totalResumoColapsado,
    required this.onExpandirPainel,
    required this.orcamentoEmEdicao,
    required this.orcamentoEmEdicaoNumero,
    this.ultimoOrcamentoSalvoNumero,
    this.ultimoOrcamentoSalvoTotal,
    required this.onCancelarEdicaoOrcamento,
    required this.mostrarDicaAtalhosCarrinho,
    required this.resumoEntregaItens,
    required this.carrinhoBody,
    required this.subtotalProdutos,
    required this.valorFrete,
    required this.valorDesconto,
    required this.descontoConfigAtivo,
    required this.totalDestaqueValor,
    required this.formatarMoeda,
    required this.onIrPesquisaProdutos,
    required this.onRecolherCheckout,
    required this.focusSalvarOrcamento,
    required this.onContinuarFechamento,
    required this.labelBotaoContinuar,
  });

  /// Em coluna (telas estreitas), o painel ignora recolhimento e usa largura total.
  final bool leiauteEmpilhado;
  final GlobalKey keyPainel;
  final bool painelCheckoutRecolhido;
  final int carrinhoCount;
  final String totalResumoColapsado;
  final VoidCallback onExpandirPainel;
  final bool orcamentoEmEdicao;
  final String? orcamentoEmEdicaoNumero;
  final int? ultimoOrcamentoSalvoNumero;
  final double? ultimoOrcamentoSalvoTotal;
  final VoidCallback onCancelarEdicaoOrcamento;
  final bool mostrarDicaAtalhosCarrinho;
  final String resumoEntregaItens;
  final Widget carrinhoBody;
  final double subtotalProdutos;
  final double valorFrete;
  final double valorDesconto;
  final bool descontoConfigAtivo;
  final double totalDestaqueValor;
  final String Function(double) formatarMoeda;
  final VoidCallback onIrPesquisaProdutos;
  final VoidCallback onRecolherCheckout;
  final FocusNode focusSalvarOrcamento;
  final VoidCallback onContinuarFechamento;
  final String labelBotaoContinuar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final efetivamenteRecolhido =
        painelCheckoutRecolhido && !leiauteEmpilhado;
    return AnimatedContainer(
      key: keyPainel,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: leiauteEmpilhado
          ? double.infinity
          : (efetivamenteRecolhido ? 64 : 470),
      child: efetivamenteRecolhido
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  IconButton(
                    tooltip: 'Expandir checkout',
                    onPressed: onExpandirPainel,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$carrinhoCount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'itens',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Divider(
                    height: 20,
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      totalResumoColapsado,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.045),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  visualDensity: VisualDensity.compact,
                  inputDecorationTheme: Theme.of(context).inputDecorationTheme
                      .copyWith(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                children: [
                                  TextSpan(
                                    text:
                                        'Venda em atendimento · $carrinhoCount itens',
                                  ),
                                  if (resumoEntregaItens.isNotEmpty) ...[
                                    TextSpan(
                                      text: ' · Entrega: $resumoEntregaItens',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  if (!orcamentoEmEdicao &&
                                      ultimoOrcamentoSalvoNumero != null)
                                    TextSpan(
                                      text:
                                          ' · Ultimo orcamento: $ultimoOrcamentoSalvoNumero'
                                          '${ultimoOrcamentoSalvoTotal != null && ultimoOrcamentoSalvoTotal! > 0.009 ? ' · ${formatarMoeda(ultimoOrcamentoSalvoTotal!)}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip:
                                'Pesquisar produto (Enter abre consulta)',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: onIrPesquisaProdutos,
                            icon: const Icon(Icons.search, size: 20),
                          ),
                          if (!leiauteEmpilhado)
                            IconButton(
                              tooltip: 'Recolher checkout',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              onPressed: onRecolherCheckout,
                              icon: const Icon(Icons.chevron_right, size: 20),
                            ),
                        ],
                      ),
                      if (orcamentoEmEdicao)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Editando venda ${orcamentoEmEdicaoNumero ?? '-'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: scheme.primary,
                                      ),
                                ),
                              ),
                              TextButton(
                                onPressed: onCancelarEdicaoOrcamento,
                                child: const Text('Cancelar edicao'),
                              ),
                            ],
                          ),
                        ),
                      if (mostrarDicaAtalhosCarrinho)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: PdvAtalhosAjudaCarrinho(),
                        ),
                      const SizedBox(height: 2),
                      Expanded(child: carrinhoBody),
                      const SizedBox(height: 6),
                      _PdvCheckoutTotaisBase(
                        scheme: scheme,
                        subtotal: subtotalProdutos,
                        frete: valorFrete,
                        desconto: valorDesconto,
                        descontoConfigAtivo: descontoConfigAtivo,
                        totalDestaque: totalDestaqueValor,
                        formatarMoeda: formatarMoeda,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: Focus(
                          focusNode: focusSalvarOrcamento,
                          child: FilledButton.icon(
                            onPressed: onContinuarFechamento,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.arrow_forward, size: 20),
                            label: Text(labelBotaoContinuar),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PdvCheckoutTotaisBase extends StatelessWidget {
  const _PdvCheckoutTotaisBase({
    required this.scheme,
    required this.subtotal,
    required this.frete,
    required this.desconto,
    required this.descontoConfigAtivo,
    required this.totalDestaque,
    required this.formatarMoeda,
  });

  final ColorScheme scheme;
  final double subtotal;
  final double frete;
  final double desconto;
  final bool descontoConfigAtivo;
  final double totalDestaque;
  final String Function(double) formatarMoeda;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mostrarDesconto = descontoConfigAtivo && desconto > 0.004;
    final mostrarFrete = frete > 0.004;
    final partes = <String>[
      'Sub ${formatarMoeda(subtotal)}',
      if (mostrarFrete) 'Frete ${formatarMoeda(frete)}',
      if (mostrarDesconto) 'Desc -${formatarMoeda(desconto)}',
    ];
    final rotuloTotal =
        descontoConfigAtivo ? 'Total a pagar' : 'Total geral';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              partes.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    rotuloTotal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  formatarMoeda(totalDestaque),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdicionarOrcamentoResult {
  const _AdicionarOrcamentoResult({
    required this.quantidadeVenda,
    required this.precoTipo,
    required this.tipoEntregaItem,
    this.quantidadeEmUnidadeCompra = false,
  });
  final double quantidadeVenda;
  final String precoTipo;
  final String tipoEntregaItem;
  final bool quantidadeEmUnidadeCompra;
}

class _DividirLinhaCarrinhoResult {
  const _DividirLinhaCarrinhoResult({
    required this.quantidadeNovaLinha,
    required this.tipoEntregaItem,
  });

  final int quantidadeNovaLinha;
  final String tipoEntregaItem;
}

class _DividirLinhaCarrinhoDialog extends StatefulWidget {
  const _DividirLinhaCarrinhoDialog({
    required this.nomeProduto,
    required this.quantidadeTotal,
    required this.tipoAtual,
  });

  final String nomeProduto;
  final int quantidadeTotal;
  final String tipoAtual;

  @override
  State<_DividirLinhaCarrinhoDialog> createState() =>
      _DividirLinhaCarrinhoDialogState();
}

class _DividirLinhaCarrinhoDialogState extends State<_DividirLinhaCarrinhoDialog> {
  late final TextEditingController _qtdController;
  late String _tipoNovaLinha;

  @override
  void initState() {
    super.initState();
    _qtdController = TextEditingController(text: '1');
    _tipoNovaLinha = EntregaVendaHelper.proximoTipoItem(widget.tipoAtual);
  }

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final q = int.tryParse(_qtdController.text.trim());
    if (q == null || q <= 0 || q >= widget.quantidadeTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Informe de 1 a ${widget.quantidadeTotal - 1} unidades para o novo item.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _DividirLinhaCarrinhoResult(
        quantidadeNovaLinha: q,
        tipoEntregaItem: _tipoNovaLinha,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restante = widget.quantidadeTotal -
        (int.tryParse(_qtdController.text.trim()) ?? 0);
    return AlertDialog(
      title: const Text('Dividir Item'),
      content: AdaptiveDialogPane(
        desktopWidth: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.nomeProduto,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Neste item: ${widget.quantidadeTotal} un. · '
              'atual: ${EntregaVendaHelper.rotuloTipoItem(widget.tipoAtual)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qtdController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Quantidade no novo item',
                helperText:
                    'Este item ficara com ${restante.clamp(0, widget.quantidadeTotal)} un.',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) => _confirmar(),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_tipoNovaLinha),
              initialValue: _tipoNovaLinha,
              decoration: const InputDecoration(
                labelText: 'Entrega do novo item',
              ),
              items: EntregaVendaHelper.tiposItem
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(EntregaVendaHelper.rotuloTipoItem(t)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tipoNovaLinha = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Dividir'),
        ),
      ],
    );
  }
}

class _EntregaDialogResult {
  const _EntregaDialogResult({
    required this.valorFrete,
    required this.endereco,
    required this.observacao,
    required this.indiceEnderecoSelecionado,
  });

  final String valorFrete;
  final String endereco;
  final String observacao;
  final int indiceEnderecoSelecionado;
}

class _EntregaClienteDialog extends StatefulWidget {
  const _EntregaClienteDialog({
    required this.clienteNome,
    required this.valorFreteInicial,
    required this.enderecosDisponiveis,
    required this.indiceEnderecoInicial,
    required this.enderecoInicial,
    required this.observacaoInicial,
  });

  final String clienteNome;
  final String valorFreteInicial;
  final List<EnderecoCliente> enderecosDisponiveis;
  final int indiceEnderecoInicial;
  final String enderecoInicial;
  final String observacaoInicial;

  @override
  State<_EntregaClienteDialog> createState() => _EntregaClienteDialogState();
}

class _EntregaClienteDialogState extends State<_EntregaClienteDialog> {
  late final TextEditingController _freteController;
  late final TextEditingController _enderecoController;
  late final TextEditingController _obsController;
  late int _indiceEnderecoSelecionado;

  @override
  void initState() {
    super.initState();
    _freteController = TextEditingController(text: widget.valorFreteInicial);
    _enderecoController = TextEditingController(text: widget.enderecoInicial);
    _obsController = TextEditingController(text: widget.observacaoInicial);
    _indiceEnderecoSelecionado = widget.enderecosDisponiveis.isEmpty
        ? 0
        : widget.indiceEnderecoInicial.clamp(
            0,
            widget.enderecosDisponiveis.length - 1,
          );
  }

  @override
  void dispose() {
    _freteController.dispose();
    _enderecoController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (_enderecoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o endereco de entrega para continuar.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      _EntregaDialogResult(
        valorFrete: _freteController.text.trim(),
        endereco: _enderecoController.text.trim(),
        observacao: _obsController.text.trim(),
        indiceEnderecoSelecionado: _indiceEnderecoSelecionado,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _confirmar,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirmar,
      },
      child: AlertDialog(
        title: Text('Entrega de ${widget.clienteNome}'),
        content: AdaptiveDialogPane(
          desktopWidth: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _freteController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor do frete',
                    hintText: 'Ex.: 35,00',
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.enderecosDisponiveis.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _indiceEnderecoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Endereco do cliente',
                    ),
                    selectedItemBuilder: (context) {
                      return List.generate(
                        widget.enderecosDisponiveis.length,
                        (index) {
                          final endereco = widget.enderecosDisponiveis[index];
                          final rotulo = endereco.rotulo.trim().isNotEmpty
                              ? endereco.rotulo.trim()
                              : 'Endereco ${index + 1}';
                          final resumo = endereco.resumo();
                          final texto = resumo.isEmpty
                              ? rotulo
                              : '$rotulo - $resumo';
                          return Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              texto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      );
                    },
                    items: List.generate(widget.enderecosDisponiveis.length, (
                      index,
                    ) {
                      final endereco = widget.enderecosDisponiveis[index];
                      final rotulo = endereco.rotulo.trim().isNotEmpty
                          ? endereco.rotulo.trim()
                          : 'Endereco ${index + 1}';
                      final resumo = endereco.resumo();
                      final texto = resumo.isEmpty
                          ? rotulo
                          : '$rotulo - $resumo';
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          texto,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _indiceEnderecoSelecionado = value;
                        final endereco = widget.enderecosDisponiveis[value];
                        _enderecoController.text = endereco.resumo();
                        _obsController.text = endereco.referencia.trim();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _enderecoController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Endereco de entrega',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _obsController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Observacoes da entrega',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar (Esc)'),
          ),
          ElevatedButton(
            onPressed: _confirmar,
            child: const Text('Confirmar (Enter)'),
          ),
        ],
      ),
    );
  }
}

class _AdicionarAoOrcamentoDialog extends StatefulWidget {
  const _AdicionarAoOrcamentoDialog({
    required this.produtoRepository,
    required this.produto,
    required this.precoTipoInicial,
    required this.tipoEntregaInicial,
    required this.precoUnitarioDe,
    required this.formatarMoeda,
  });

  final ProdutoRepository produtoRepository;
  final Produto produto;
  final String precoTipoInicial;
  final String tipoEntregaInicial;
  final double Function(Produto produto, String precoTipo) precoUnitarioDe;
  final String Function(double) formatarMoeda;

  @override
  State<_AdicionarAoOrcamentoDialog> createState() =>
      _AdicionarAoOrcamentoDialogState();
}

class _AdicionarAoOrcamentoDialogState
    extends State<_AdicionarAoOrcamentoDialog> {
  late Produto _produto;
  late String _precoTipo;
  late String _tipoEntrega;
  late bool _quantidadeEmUnidadeCompra;
  late final TextEditingController _qtdController;
  final _qtdFocus = FocusNode(debugLabel: 'pdvDialogQtd');

  void _recarregarProdutoDoBanco() {
    final fresh = widget.produtoRepository.obterPorId(widget.produto.id);
    if (fresh != null) {
      _produto = fresh;
    }
  }

  @override
  void initState() {
    super.initState();
    _produto = widget.produto;
    _recarregarProdutoDoBanco();
    _precoTipo = widget.precoTipoInicial;
    _tipoEntrega = EntregaVendaHelper.normalizarTipoItem(
      widget.tipoEntregaInicial,
    );
    _quantidadeEmUnidadeCompra = false;
    _qtdController = TextEditingController(text: '1');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _qtdFocus.requestFocus();
        _qtdController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _qtdController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _qtdController.dispose();
    _qtdFocus.dispose();
    super.dispose();
  }

  void _confirmar() {
    _recarregarProdutoDoBanco();
    final fracionada = _produto.permiteQuantidadeFracionada &&
        !_quantidadeEmUnidadeCompra;
    final textoQtd = _qtdController.text;
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      textoQtd,
      fracionada: fracionada,
    );
    if (q == null) {
      final pareceDecimal =
          QuantidadeVendaUtil.textoPareceQuantidadeDecimal(textoQtd);
      final comoFracionada = QuantidadeVendaUtil.parseEntradaPdv(
        textoQtd,
        fracionada: true,
      );
      String msg;
      if (pareceDecimal &&
          comoFracionada != null &&
          !_produto.permiteQuantidadeFracionada) {
        msg =
            'Este produto ainda nao esta com "Permite venda fracionada" no PDV. '
            'Salve no cadastro, feche este dialogo, pesquise o produto de novo '
            'e tente outra vez.';
      } else if (fracionada) {
        msg = 'Informe uma quantidade maior que zero (ex.: 4,50 ou 1.5).';
      } else {
        msg = 'Informe uma quantidade inteira maior que zero.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      return;
    }
    Navigator.of(context).pop(
      _AdicionarOrcamentoResult(
        quantidadeVenda: q,
        precoTipo: _precoTipo,
        tipoEntregaItem: _tipoEntrega,
        quantidadeEmUnidadeCompra: _quantidadeEmUnidadeCompra,
      ),
    );
  }

  String _previewSubtotalLinha(double precoUnit, bool fracionada) {
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      _qtdController.text,
      fracionada: fracionada,
    );
    if (q == null) return '';
    return ' · Subtotal: ${widget.formatarMoeda(q * precoUnit)}';
  }

  String? _previewConversaoEstoque() {
    if (!_quantidadeEmUnidadeCompra ||
        !_produto.pdvPodeVenderEmUnidadeCompra) {
      return null;
    }
    final q = int.tryParse(_qtdController.text.trim()) ?? 0;
    if (q <= 0) return null;
    final qEst = ProdutoEmbalagem.quantidadeVendaParaEstoque(
      produto: _produto,
      quantidadeDigitada: q,
      emUnidadeCompra: true,
    );
    final uVenda = ProdutoEmbalagem.normalizarUnidade(_produto.unidade);
    return 'Baixa de estoque: $qEst $uVenda';
  }

  @override
  Widget build(BuildContext context) {
    final precoUnit = widget.precoUnitarioDe(_produto, _precoTipo);
    final fracionada =
        _produto.permiteQuantidadeFracionada && !_quantidadeEmUnidadeCompra;
    final podeEmbalagem = _produto.pdvPodeVenderEmUnidadeCompra;
    final uCompra =
        ProdutoEmbalagem.normalizarUnidade(_produto.unidadeCompraEfetiva);
    final uVenda = ProdutoEmbalagem.normalizarUnidade(_produto.unidade);
    final previewEstoque = _previewConversaoEstoque();
    return AlertDialog(
      title: Text('Adicionar: ${_produto.nome}'),
      content: AdaptiveDialogPane(
        desktopWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fracionada)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.straighten, size: 18),
                    label: Text(
                      'Venda fracionada ($uVenda) — use 4,50 ou 4.5',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            DropdownButtonFormField<String>(
              key: ValueKey(_precoTipo),
              initialValue: _precoTipo,
              decoration: const InputDecoration(labelText: 'Tipo de preco'),
              items: const [
                DropdownMenuItem(value: 'preco1', child: Text('A Prazo')),
                DropdownMenuItem(value: 'preco2', child: Text('À Vista')),
                DropdownMenuItem(value: 'preco3', child: Text('Atacado')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _precoTipo = value);
                }
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_tipoEntrega),
              initialValue: _tipoEntrega,
              decoration: const InputDecoration(labelText: 'Entrega deste item'),
              items: EntregaVendaHelper.tiposItem
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(EntregaVendaHelper.rotuloTipoItem(t)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _tipoEntrega = value);
              },
            ),
            if (podeEmbalagem) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(uVenda)),
                  ButtonSegment(value: true, label: Text(uCompra)),
                ],
                selected: {_quantidadeEmUnidadeCompra},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _quantidadeEmUnidadeCompra = s.first);
                },
              ),
              if (_produto.rotuloConversaoEmbalagem.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _produto.rotuloConversaoEmbalagem,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextFormField(
              controller: _qtdController,
              focusNode: _qtdFocus,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _quantidadeEmUnidadeCompra && podeEmbalagem
                    ? 'Quantidade ($uCompra)'
                    : 'Quantidade ($uVenda)',
                helperText: previewEstoque ??
                    (fracionada
                        ? 'Permite decimais (ex.: 4,50 ou 4.50).'
                        : 'Somente quantidade inteira. Para vender fracionado, '
                            'ative "Permite venda fracionada" no cadastro do produto.'),
              ),
              keyboardType: fracionada
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) => _confirmar(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preco por $uVenda: ${widget.formatarMoeda(precoUnit)}'
                '${_previewSubtotalLinha(precoUnit, fracionada)}',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Adicionar')),
      ],
    );
  }
}

/// F1/F3 alternam a tabela de preco (carrinho inteiro e novos itens).
class SelecionarPrecoListaIntent extends Intent {
  const SelecionarPrecoListaIntent(this.precoTipo);
  final String precoTipo;
}

/// Ctrl+F1/F2/F3 alternam entrega no carrinho inteiro (tecla E na linha).
class SelecionarEntregaPadraoIntent extends Intent {
  const SelecionarEntregaPadraoIntent(this.tipoEntrega);
  final String tipoEntrega;
}

class PdvAbrirConsultaIntent extends Intent {
  const PdvAbrirConsultaIntent();
}

class PdvFocarPesquisaProdutosIntent extends Intent {
  const PdvFocarPesquisaProdutosIntent();
}

class PdvRecarregarProdutosIntent extends Intent {
  const PdvRecarregarProdutosIntent();
}

class PdvFocarCarrinhoIntent extends Intent {
  const PdvFocarCarrinhoIntent();
}

class PdvSalvarOrcamentoIntent extends Intent {
  const PdvSalvarOrcamentoIntent();
}

class PdvLerOrcamentoIntent extends Intent {
  const PdvLerOrcamentoIntent();
}

class PdvLimparPesquisaIntent extends Intent {
  const PdvLimparPesquisaIntent();
}

class PdvToggleCalculadoraIntent extends Intent {
  const PdvToggleCalculadoraIntent();
}

class _OrcamentoItemDraft implements PromocaoCarrinhoLinha {
  _OrcamentoItemDraft({
    required this.produto,
    required this.quantidade,
    required this.precoTipo,
    required this.precoUnitario,
    this.tipoEntregaItem = EntregaVendaHelper.tipoRetirada,
    this.quantidadeEmUnidadeCompra = false,
    this.promocaoId = 0,
    this.promocaoNome = '',
    this.precoUnitarioManual = false,
  });

  @override
  final Produto produto;
  int quantidade;
  @override
  String precoTipo;
  @override
  double precoUnitario;
  String tipoEntregaItem;
  final bool quantidadeEmUnidadeCompra;
  @override
  int promocaoId;
  @override
  String promocaoNome;
  bool precoUnitarioManual;

  @override
  bool get precoManual => precoUnitarioManual;

  @override
  int get quantidadeEstoque => ProdutoEmbalagem.quantidadeVendaParaEstoque(
        produto: produto,
        quantidadeDigitada: QuantidadeVendaUtil.paraEstoqueInteiro(
          produto,
          quantidade,
        ),
        emUnidadeCompra: quantidadeEmUnidadeCompra,
      );

  String get rotuloQuantidadeCarrinho =>
      ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: quantidade,
        emUnidadeCompra: quantidadeEmUnidadeCompra,
      );

  double get subtotal =>
      QuantidadeVendaUtil.valorExibicao(
        quantidade,
        fracionada: produto.permiteQuantidadeFracionada,
      ) *
      precoUnitario;
}

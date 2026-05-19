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
import '../domain/pagamento_orcamento.dart';
import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/kit_orcamento_repository.dart';
import '../data/produto_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/sync/safe_sync_refresh_mixin.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import '../model/item_venda.dart';
import '../model/kit_orcamento.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import '../model/vendedor.dart';
import '../services/cupom_pdf_layout.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'pdv_consulta_produtos_page.dart';
import 'widgets/pdv_carrinho_linha_compacta.dart';
import 'widgets/pdv_tipo_entrega_item.dart';

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
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;

  @override
  State<PontoDeVendaPage> createState() => _PontoDeVendaPageState();
}

class _PontoDeVendaPageState extends State<PontoDeVendaPage> with SafeSyncRefreshMixin {
  static const int _validadeOrcamentoDias = 7;
  static const int _selecaoSemClienteValor = -1;
  static const int _selecaoNovoClienteValor = -2;

  final _pesquisaController = TextEditingController();
  final _pesquisaFocus = FocusNode(debugLabel: 'pesquisaPdV');
  final _carrinhoFocus = FocusNode(debugLabel: 'carrinhoPdV');

  /// Checkout à direita (F7 / Shift+F7).
  final _focusClientePdV = FocusNode(debugLabel: 'pdvCliente');
  final _focusVendedorPdV = FocusNode(debugLabel: 'pdvVendedor');
  final _focusPagamentoPdV = FocusNode(debugLabel: 'pdvPagamento');
  final _focusParcelasPdV = FocusNode(debugLabel: 'pdvParcelas');

  /// Botão "Editar dados da entrega" (frete/endereço estão no dialogo).
  final _focusEditarEntregaPdV = FocusNode(debugLabel: 'pdvEditarEntrega');
  final _focusSalvarOrcamentoPdV = FocusNode(debugLabel: 'pdvSalvarOrcamento');

  /// Produtos usados recentemente nesta sessao (consulta vazia).
  final List<int> _produtosRecentesPdv = [];

  /// Ancora o painel direito para saber se o foco realmente esta no checkout (hasFocus dos nos falha).
  final GlobalKey _keyPainelCheckoutPdV = GlobalKey();
  final _valorFreteController = TextEditingController();
  final _enderecoEntregaController = TextEditingController();
  final _observacaoEntregaController = TextEditingController();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  late final KitOrcamentoRepository _kitOrcamentoRepo =
      KitOrcamentoRepository(widget.produtoRepository.objectBox);
  List<Cliente> _clientes = [];
  List<Vendedor> _vendedoresAtivos = [];
  final List<_OrcamentoItemDraft> _carrinho = [];

  /// Linha selecionada no carrinho (para ↑↓ ajustar quantidade).
  int? _indiceLinhaCarrinho;

  /// Preco usado em adicao rapida e exibido na linha (F1/F2/F3).
  String _precoListaAtivo = 'preco1';
  String _formaPagamentoSelecionada = 'dinheiro';
  int _parcelasSelecionadas = 1;
  bool _pagamentoMistoPdV = false;
  final List<_LinhaPagamentoMistoPdV> _linhasPagamentoMisto = [];
  static const double _valorMinimoParcelaCreditoPdV = 5.0;
  int? _clienteSelecionadoId;
  int _indiceEnderecoSelecionado = 0;
  int? _vendedorSelecionadoId;
  /// Padrao ao adicionar novos itens ao carrinho (nao altera linhas existentes).
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

  IconData _iconePrecoLista(String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return Icons.payments_outlined;
      case 'preco3':
        return Icons.storefront_outlined;
      case 'preco1':
      default:
        return Icons.calendar_month_outlined;
    }
  }

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

  Widget _buildBotaoPrecoListaAppBar() {
    final tipo = _precoListaAtivo;
    final rotulo = _rotuloPreco(tipo);
    return PopupMenuButton<String>(
      tooltip: 'Lista de preco para novos itens: $rotulo (F1–F3)',
      onSelected: (value) => setState(() => _precoListaAtivo = value),
      icon: Icon(
        _iconePrecoLista(tipo),
        color: _corPrecoLista(context, tipo),
      ),
      itemBuilder: (context) {
        final labelSmall = Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            );
        return [
          for (final opcao in _opcoesPrecoListaPdv)
            PopupMenuItem<String>(
              value: opcao.$1,
              child: Row(
                children: [
                  Icon(
                    _iconePrecoLista(opcao.$1),
                    size: 20,
                    color: _corPrecoLista(context, opcao.$1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(opcao.$2),
                        Text(opcao.$3, style: labelSmall),
                      ],
                    ),
                  ),
                  if (tipo == opcao.$1)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ];
      },
    );
  }

  Widget _buildBotaoEntregaPadraoAppBar() {
    final tipo = _tipoEntregaSelecionada;
    final rotulo = EntregaVendaHelper.rotuloTipoItem(tipo);
    return PopupMenuButton<String>(
      tooltip: 'Entrega padrao para novos itens: $rotulo (Ctrl+F1–F3)',
      onSelected: (value) => setState(() => _tipoEntregaSelecionada = value),
      icon: Icon(
        PdvBotaoTipoEntregaItem.iconePara(tipo),
        color: PdvBotaoTipoEntregaItem.corPara(context, tipo),
      ),
      itemBuilder: (context) {
        final labelSmall = Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            );
        return [
          for (final opcao in _opcoesEntregaPadraoPdv)
            PopupMenuItem<String>(
              value: opcao.$1,
              child: Row(
                children: [
                  Icon(
                    PdvBotaoTipoEntregaItem.iconePara(opcao.$1),
                    size: 20,
                    color: PdvBotaoTipoEntregaItem.corPara(context, opcao.$1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(opcao.$2),
                        Text(opcao.$3, style: labelSmall),
                      ],
                    ),
                  ),
                  if (tipo == opcao.$1)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ];
      },
    );
  }

  Widget _buildBlocoEntregaItensFechamento(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resumo = _resumoEntregaItensCarrinho;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entrega dos itens desta venda',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (_carrinhoEntregaMista) ...[
            const SizedBox(height: 4),
            Text(
              'Venda mista',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (resumo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              resumo,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
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
  ) {
    final idx = _carrinho.indexWhere(
      (e) =>
          e.produto.id == produtoId &&
          e.precoTipo == precoTipo &&
          e.tipoEntregaItem == tipoEntregaItem,
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
        ),
      );
      _indiceLinhaCarrinho = index + 1;
    });
    _carrinhoFocus.requestFocus();
  }

  int _quantidadeProdutoNoCarrinho(int produtoId) {
    return _carrinho
        .where((e) => e.produto.id == produtoId)
        .fold(0, (s, e) => s + e.quantidade);
  }
  String _prioridadeEntregaSelecionada = 'normal';
  String _janelaEntregaSelecionada = 'nao_definida';
  DateTime? _dataEntregaMarcada;
  bool _permitirVendaSemEstoque = true;
  double _maxDescontoPercentualPdv = 15;

  /// `percentual` | `valor` — desconto sempre limitado ao configurado (% sobre subtotal).
  String _tipoDescontoPdV = 'percentual';
  final _descontoPdVController = TextEditingController();
  int? _orcamentoEmEdicaoId;
  int? _orcamentoEmEdicaoNumero;
  bool _mostrarAjudaAtalhos = false;

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
    HardwareKeyboard.instance.addHandler(_handlerCheckoutF7PdV);
    widget.produtoRepository.addListener(_onProdutoRepositoryChanged);
    initSafeSyncRefresh(
      onReload: _recarregarDadosSync,
      bloquearAtualizacao: _bloquearSyncPdv,
      aoConcluir: _snackbarDadosAtualizados,
    );
    _carregarDadosIniciais();
    _carregarConfiguracaoVendaSemEstoque();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pesquisaFocus.requestFocus();
    });
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
      _maxDescontoPercentualPdv = config.maxDescontoPercentualPdv;
    });
  }

  @override
  void dispose() {
    disposeSafeSyncRefresh();
    widget.produtoRepository.removeListener(_onProdutoRepositoryChanged);
    HardwareKeyboard.instance.removeHandler(_handlerCheckoutF7PdV);
    _checkoutF7BurstId = 0;
    _carrinhoFocus.dispose();
    _focusClientePdV.dispose();
    _focusVendedorPdV.dispose();
    _focusPagamentoPdV.dispose();
    _focusParcelasPdV.dispose();
    _focusEditarEntregaPdV.dispose();
    _focusSalvarOrcamentoPdV.dispose();
    _descontoPdVController.dispose();
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
    return out;
  }

  void _registrarProdutoRecente(Produto produto) {
    _produtosRecentesPdv.remove(produto.id);
    _produtosRecentesPdv.insert(0, produto.id);
    if (_produtosRecentesPdv.length > 20) {
      _produtosRecentesPdv.removeRange(20, _produtosRecentesPdv.length);
    }
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
          precoUnitarioDe: _precoPorTipo,
        ),
      ),
    );

    if (!mounted) return;
    _pesquisaController.clear();
    _voltarFocoParaPesquisa();

    if (result == null) return;

    setState(() => _precoListaAtivo = result.precoListaAtivo);
    _registrarProdutoRecente(result.produto);

    if (result.adicaoDireta) {
      _adicionarComQuantidade(
        result.produto,
        1,
        precoTipo: result.precoListaAtivo,
      );
      return;
    }
    if (result.quantidadeDireta != null) {
      _adicionarComQuantidade(
        result.produto,
        result.quantidadeDireta!,
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

  /// Unico handler para F7 (evita Shortcuts disparar duas vezes no desktop).
  bool _handlerCheckoutF7PdV(KeyEvent event) {
    if (!mounted) return false;
    if (event.logicalKey != LogicalKeyboardKey.f7) return false;

    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;

    if (event is KeyRepeatEvent) {
      return true;
    }

    if (event is! KeyDownEvent) return false;

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
    if (_carrinho.isNotEmpty) {
      setState(() {
        _indiceLinhaCarrinho = (_indiceLinhaCarrinho ?? _carrinho.length - 1)
            .clamp(0, _carrinho.length - 1);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
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

  void _adicionarComQuantidade(
    Produto produto,
    int quantidade, {
    String? precoTipo,
    String? tipoEntregaItem,
  }) {
    if (quantidade <= 0) return;
    final preco = precoTipo ?? _precoListaAtivo;
    final unit = _precoPorTipo(produto, preco);
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
      if (jaNoCarrinho + quantidade > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo para ${produto.nome}: $disp (ja ha $jaNoCarrinho no orcamento).',
            ),
          ),
        );
        return;
      }
    }
    final tipoNovo = EntregaVendaHelper.normalizarTipoItem(
      tipoEntregaItem ?? _tipoEntregaSelecionada,
    );
    final idxExistente = _indiceLinhaParaMesclar(produto.id, preco, tipoNovo);
    setState(() {
      if (idxExistente != null) {
        _carrinho[idxExistente].quantidade += quantidade;
        _indiceLinhaCarrinho = idxExistente;
      } else {
        _carrinho.add(
          _OrcamentoItemDraft(
            produto: produto,
            quantidade: quantidade,
            precoTipo: preco,
            precoUnitario: unit,
            tipoEntregaItem: tipoNovo,
          ),
        );
        _indiceLinhaCarrinho = _carrinho.length - 1;
      }
    });
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
              content: SizedBox(
                width: 380,
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
      _adicionarComQuantidade(p, q);
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

  void _alterarQuantidadeCarrinho(int index, int delta) {
    if (!_permitirVendaSemEstoque && delta > 0) {
      final item = _carrinho[index];
      final fresh =
          widget.produtoRepository.obterPorId(item.produto.id) ?? item.produto;
      final disp = fresh.estoqueLivreParaVenda;
      if (item.quantidade + delta > disp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque maximo: $disp (atual no orcamento: ${item.quantidade}).',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      final item = _carrinho[index];
      final nova = item.quantidade + delta;
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

  /// Setas na lista de **carrinho** (foco no orcamento): quantidade; Ctrl+setas = outra linha.
  KeyEventResult _onKeyCarrinho(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_carrinho.isEmpty) return KeyEventResult.ignored;

    final n = _carrinho.length;
    var idx = _indiceLinhaCarrinho ?? 0;
    idx = idx.clamp(0, n - 1);
    final ctrl = _ctrlPressionado();

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
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      _alterarQuantidadeCarrinho(idx, 1);
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      _alterarQuantidadeCarrinho(idx, -1);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _indiceLinhaCarrinho = (idx + 1).clamp(0, n - 1);
      });
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _indiceLinhaCarrinho = (idx - 1).clamp(0, n - 1);
      });
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _alterarQuantidadeCarrinho(idx, 1);
      return KeyEventResult.handled;
    }
    if (!ctrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _alterarQuantidadeCarrinho(idx, -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _carregarDadosIniciais() {
    setState(() {
      _clientes = widget.clienteRepository
          .listarTodos()
          .where((c) => c.ativo)
          .toList();
      _vendedoresAtivos = widget.vendedorRepository.listarAtivos();
    });
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
    return _clientes.where((c) => c.id == id).firstOrNull;
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

  Future<void> _selecionarClienteNoOrcamento(int? value) async {
    if (value == null) {
      setState(() {
        _clienteSelecionadoId = null;
        _indiceEnderecoSelecionado = 0;
        _tipoEntregaSelecionada = EntregaVendaHelper.tipoRetirada;
        _prioridadeEntregaSelecionada = 'normal';
        _janelaEntregaSelecionada = 'nao_definida';
        _dataEntregaMarcada = null;
        _valorFreteController.clear();
        _enderecoEntregaController.clear();
        _observacaoEntregaController.clear();
      });
      return;
    }
    final cliente = _clientes.where((c) => c.id == value).firstOrNull;
    if (cliente == null) return;
    setState(() {
      _clienteSelecionadoId = value;
      _aplicarEnderecoSelecionadoDoCliente(cliente, 0);
    });
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
          retornarClienteAoSalvar: true,
        ),
      ),
    );
    if (!mounted || clienteCriado == null) {
      return;
    }
    setState(() {
      _clientes = widget.clienteRepository
          .listarTodos()
          .where((c) => c.ativo)
          .toList();
    });
    await _selecionarClienteNoOrcamento(clienteCriado.id);
    setDialogState?.call(() {});
  }

  Future<void> _abrirSeletorClienteNoPdv({StateSetter? setDialogState}) async {
    final resultado = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final pesquisaController = TextEditingController();
        var filtrados = List<Cliente>.from(_clientes);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Selecionar cliente'),
              content: SizedBox(
                width: 680,
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
                        final termo = value.trim().toLowerCase();
                        final termoNumerico = value.replaceAll(
                          RegExp(r'\D'),
                          '',
                        );
                        setDialogState(() {
                          if (termo.isEmpty) {
                            filtrados = List<Cliente>.from(_clientes);
                            return;
                          }
                          filtrados = _clientes.where((cliente) {
                            final campos = [
                              cliente.nomeRazao,
                              cliente.nomeFantasia,
                              cliente.documento,
                              cliente.telefone,
                              cliente.whatsapp,
                              cliente.email,
                              cliente.cidade,
                            ].map((e) => e.toLowerCase());
                            final matchTexto = campos.any(
                              (campo) => campo.contains(termo),
                            );
                            if (matchTexto) return true;
                            if (termoNumerico.isEmpty) return false;
                            final camposNumericos = [
                              cliente.documento,
                              cliente.telefone,
                              cliente.whatsapp,
                              cliente.cep,
                            ].map((e) => e.replaceAll(RegExp(r'\D'), ''));
                            return camposNumericos.any(
                              (campoNumerico) =>
                                  campoNumerico.contains(termoNumerico),
                            );
                          }).toList();
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
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
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

    if (!mounted || resultado == null) {
      return;
    }
    if (resultado == _selecaoNovoClienteValor) {
      await _abrirCadastroNovoClienteNoPdv(setDialogState: setDialogState);
      return;
    }
    if (resultado == _selecaoSemClienteValor) {
      await _selecionarClienteNoOrcamento(null);
      setDialogState?.call(() {});
      return;
    }
    await _selecionarClienteNoOrcamento(resultado);
    setDialogState?.call(() {});
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

  double _precoPorTipo(Produto produto, String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
      case 'preco3':
        return produto.preco3 > 0 ? produto.preco3 : produto.precoVenda;
      case 'preco1':
      default:
        return produto.preco1 > 0 ? produto.preco1 : produto.precoVenda;
    }
  }

  String _rotuloPreco(String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return 'À Vista';
      case 'preco3':
        return 'Atacado';
      case 'preco1':
      default:
        return 'A Prazo';
    }
  }

  Future<void> _adicionarAoOrcamento(Produto produto) async {
    final result = await showDialog<_AdicionarOrcamentoResult>(
      context: context,
      builder: (context) => _AdicionarAoOrcamentoDialog(
        produto: produto,
        precoTipoInicial: _precoListaAtivo,
        tipoEntregaInicial: _tipoEntregaSelecionada,
        precoUnitarioDe: (t) => _precoPorTipo(produto, t),
        formatarMoeda: _formatarMoeda,
      ),
    );

    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (result.quantidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade deve ser maior que zero.')),
      );
      return;
    }

    _adicionarComQuantidade(
      produto,
      result.quantidade,
      precoTipo: result.precoTipo,
      tipoEntregaItem: result.tipoEntregaItem,
    );
  }

  static const List<String> _meiosPagamentoMistoPdV = [
    'dinheiro',
    'pix',
    'cartao_credito',
    'cartao_debito',
    'transferencia',
  ];

  Widget _buildPainelPagamentoMistoPdV(StateSetter setDialogState) {
    final restante = _totalLiquidoPagamentoPdV() - _somaDigitadaMistoPdV();
    final ok = restante.abs() < 0.02;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_linhasPagamentoMisto.length, (i) {
          final linha = _linhasPagamentoMisto[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: linha.meio,
                    decoration: const InputDecoration(labelText: 'Meio'),
                    items: _meiosPagamentoMistoPdV
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(_rotuloFormaPagamento(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      _atualizarCheckoutFechamento(setDialogState, () {
                        linha.meio = v;
                        if (v != 'cartao_credito') linha.parcelas = 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: linha.valorController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      hintText: '0,00',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ),
                if (linha.meio == 'cartao_credito') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: DropdownButtonFormField<int>(
                      initialValue: linha.parcelas.clamp(1, 12),
                      decoration: const InputDecoration(labelText: 'Parc.'),
                      items: List.generate(
                        12,
                        (k) => DropdownMenuItem(
                          value: k + 1,
                          child: Text('${k + 1}x'),
                        ),
                      ),
                      onChanged: (p) {
                        if (p != null) {
                          _atualizarCheckoutFechamento(setDialogState, () {
                            linha.parcelas = p;
                          });
                        }
                      },
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Remover parte',
                  onPressed: _linhasPagamentoMisto.length <= 2
                      ? null
                      : () {
                          _atualizarCheckoutFechamento(setDialogState, () {
                            final rem = _linhasPagamentoMisto.removeAt(i);
                            rem.dispose();
                          });
                        },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
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

  Future<void> _abrirPassoFechamentoVenda() async {
    _descontoPdVController.clear();
    _tipoDescontoPdV = 'percentual';
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    _aplicarEnderecoCarretoDoClienteSeVazio();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _orcamentoEmEdicaoId != null
                    ? 'Concluir atualizacao da venda'
                    : 'Dados para enviar ao caixa',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
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
                    child: _buildFormularioFechamentoVenda(
                      setDialogState: setDialogState,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Voltar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    await _salvarOrcamento(
                      fechamentoDialogContext: dialogContext,
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _orcamentoEmEdicaoId != null
                        ? 'Confirmar atualizacao'
                        : 'Confirmar e enviar ao caixa',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// O dialog de fechamento e uma rota overlay; `setState` na pagina nao redesenha o
  /// AlertDialog. Este helper atualiza o estado da pagina e forca o rebuild do dialog.
  void _atualizarCheckoutFechamento(
    StateSetter setDialogState,
    VoidCallback fn,
  ) {
    setState(fn);
    setDialogState(() {});
  }

  Widget _buildFormularioFechamentoVenda({
    required StateSetter setDialogState,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Subtotal produtos: ${_formatarMoeda(_totalOrcamento)}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 2),
        Text(
          'Frete: ${_formatarMoeda(_valorFreteAtual)}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 2),
        if (_maxDescontoPercentualPdv > 0) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'percentual',
                      label: Text('%'),
                    ),
                    ButtonSegment<String>(value: 'valor', label: Text('R\$')),
                  ],
                  selected: {_tipoDescontoPdV},
                  onSelectionChanged: (values) {
                    _atualizarCheckoutFechamento(setDialogState, () {
                      _tipoDescontoPdV = values.first;
                      _descontoPdVController.clear();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _descontoPdVController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _tipoDescontoPdV == 'percentual'
                        ? 'Desconto % (subtotal produtos)'
                        : 'Desconto em reais (subtotal)',
                    helperText: _descontoPdVDigitadoUltrapassaTeto()
                        ? null
                        : 'Teto: ${_maxDescontoPercentualPdv.toStringAsFixed(1)}% '
                              'do subtotal = ${_formatarMoeda(_valorMaximoDescontoReaisPdV())}',
                    errorText: _descontoPdVDigitadoUltrapassaTeto()
                        ? _mensagemErroDescontoPdVUltrapassaTeto()
                        : null,
                    isDense: true,
                  ),
                  onChanged: (_) =>
                      _atualizarCheckoutFechamento(setDialogState, () {}),
                ),
              ),
            ],
          ),
          if (_valorDescontoReaisPdV() > 0.004) ...[
            const SizedBox(height: 4),
            Text(
              'Desconto: - ${_formatarMoeda(_valorDescontoReaisPdV())} '
              '(${_percentualEfetivoSobreSubtotalPdV().toStringAsFixed(1)}% do subtotal)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Total a pagar (caixa): ${_formatarMoeda(_totalLiquidoPagamentoPdV())}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ] else ...[
          Text(
            'Total geral: ${_formatarMoeda(_totalGeralComFrete)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 6),
        Focus(
          focusNode: _focusClientePdV,
          child: InkWell(
            onTap: () =>
                _abrirSeletorClienteNoPdv(setDialogState: setDialogState),
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cliente (opcional)',
                suffixIcon: Icon(Icons.search),
              ),
              child: Text(_rotuloClienteSelecionadoPdV()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          focusNode: _focusVendedorPdV,
          initialValue: _vendedorSelecionadoId,
          decoration: const InputDecoration(labelText: 'Vendedor (opcional)'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Sem vendedor'),
            ),
            ..._vendedoresAtivos.map(
              (v) => DropdownMenuItem<int?>(
                value: v.id,
                child: Text(_rotuloItemVendedorPdV(v)),
              ),
            ),
          ],
          onChanged: (value) {
            _atualizarCheckoutFechamento(
              setDialogState,
              () => _vendedorSelecionadoId = value,
            );
          },
        ),
        const SizedBox(height: 8),
        _buildBlocoEntregaItensFechamento(context),
        if (_carrinhoTemItemCarreto) ...[
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
                  final rotulo = endereco.rotulo.trim().isNotEmpty
                      ? endereco.rotulo.trim()
                      : 'Endereco ${index + 1}';
                  final resumo = endereco.resumo();
                  final texto =
                      resumo.isEmpty ? rotulo : '$rotulo - $resumo';
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
                final rotulo = endereco.rotulo.trim().isNotEmpty
                    ? endereco.rotulo.trim()
                    : 'Endereco ${index + 1}';
                final resumo = endereco.resumo();
                return DropdownMenuItem<int>(
                  value: index,
                  child: Text(
                    resumo.isEmpty ? rotulo : '$rotulo - $resumo',
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
                          _tipoEntregaSelecionada = 'entrega_loja';
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
        if (!_pagamentoMistoPdV) ...[
          DropdownButtonFormField<String>(
            focusNode: _focusPagamentoPdV,
            initialValue: _formaPagamentoSelecionada,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: const [
              DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
              DropdownMenuItem(value: 'pix', child: Text('PIX')),
              DropdownMenuItem(
                value: 'cartao_credito',
                child: Text('Cartao de credito'),
              ),
              DropdownMenuItem(
                value: 'cartao_debito',
                child: Text('Cartao de debito'),
              ),
              DropdownMenuItem(value: 'fiado', child: Text('Fiado')),
              DropdownMenuItem(
                value: 'transferencia',
                child: Text('Transferencia'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _atualizarCheckoutFechamento(setDialogState, () {
                _formaPagamentoSelecionada = value;
                if (_formaPagamentoSelecionada != 'cartao_credito') {
                  _parcelasSelecionadas = 1;
                }
              });
            },
          ),
          if (_formaPagamentoSelecionada == 'cartao_credito') ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey<String>(_formaPagamentoSelecionada),
              focusNode: _focusParcelasPdV,
              initialValue: _parcelasSelecionadas,
              decoration: const InputDecoration(labelText: 'Parcelas'),
              items: List.generate(
                12,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(_rotuloParcela(index + 1)),
                ),
              ),
              onChanged: (value) {
                if (value != null) {
                  _atualizarCheckoutFechamento(
                    setDialogState,
                    () => _parcelasSelecionadas = value,
                  );
                }
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Selecionado: ${_rotuloParcela(_parcelasSelecionadas)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ] else ...[
          const SizedBox(height: 6),
          _buildPainelPagamentoMistoPdV(setDialogState),
        ],
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _pagamentoMistoPdV,
          onChanged: (on) {
            _atualizarCheckoutFechamento(setDialogState, () {
              _pagamentoMistoPdV = on;
              if (on) {
                _inicializarLinhasMistoPadrao();
              } else {
                _disposeLinhasPagamentoMisto();
              }
            });
          },
          title: const Text('Pagamento misto'),
        ),
        if (_orcamentoEmEdicaoId != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Editando venda ${_orcamentoEmEdicaoNumero ?? '-'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
        ],
      ],
    );
  }

  Future<void> _salvarOrcamento({BuildContext? fechamentoDialogContext}) async {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione ao menos um item na venda.')),
      );
      return;
    }
    if (_maxDescontoPercentualPdv > 0 && _descontoPdVDigitadoUltrapassaTeto()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensagemErroDescontoPdVUltrapassaTeto())),
      );
      return;
    }
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
      final pagamento = DadosPagamentoOrcamento(
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
        );
      }
      await LanSyncScheduler.solicitarSyncImediato();
      if (!mounted) return;
      final vendaSalva = widget.vendaRepository.obterPorId(orcamentoId);
      final numeroOrcamentoSalvo =
          vendaSalva?.numeroOrcamento ?? _orcamentoEmEdicaoNumero;
      setState(() {
        _carrinho.clear();
        _pagamentoMistoPdV = false;
        _disposeLinhasPagamentoMisto();
        _formaPagamentoSelecionada = 'dinheiro';
        _parcelasSelecionadas = 1;
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
      });
      if (fechamentoDialogContext != null && fechamentoDialogContext.mounted) {
        Navigator.of(fechamentoDialogContext).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orcamentoEdicaoId != null
                ? 'Venda $numeroOrcamentoSalvo atualizada com sucesso.'
                : 'Venda $orcamentoId salva para o caixa.',
          ),
        ),
      );
      if (vendaSalva != null && mounted) {
        await _mostrarAcoesPdfOrcamento(vendaSalva);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar venda: $e')));
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

  Produto? _resolverProdutoItemOrcamento(
    ItemVenda item,
    List<Produto> todosProdutos,
  ) {
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

    final exato = todosProdutos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome == nomeItem;
    }).firstOrNull;
    if (exato != null) {
      return exato;
    }

    final aproximado = todosProdutos.where((p) {
      final nome = _normalizarTextoComparacao(p.nome);
      return nome.contains(nomeItem) || nomeItem.contains(nome);
    }).firstOrNull;
    return aproximado;
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
              content: SizedBox(
                width: 760,
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
                        minHeight: 220,
                        maxHeight: MediaQuery.of(context).size.height * 0.58,
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
    final drafts = <_OrcamentoItemDraft>[];
    final nomesItensSemProduto = <String>[];
    final todosProdutos = widget.produtoRepository.listarTodos();
    for (final item in orcamentoCompleto.itens) {
      final produto = _resolverProdutoItemOrcamento(item, todosProdutos);
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
        ),
      );
    }
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nomesItensSemProduto.isNotEmpty
                ? 'Nao foi possivel carregar itens do orcamento. Produtos sem cadastro atual.'
                : 'Nao foi possivel carregar itens do orcamento selecionado.',
          ),
        ),
      );
      return;
    }

    final clienteIdCarregado = orcamentoCompleto.cliente.targetId == 0
        ? null
        : orcamentoCompleto.cliente.targetId;
    final vendedorIdCarregado = orcamentoCompleto.vendedor.targetId == 0
        ? null
        : orcamentoCompleto.vendedor.targetId;
    final clienteIdValido =
        clienteIdCarregado != null &&
            _clientes.any((c) => c.id == clienteIdCarregado)
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
      final cliente = _clientes
          .where((c) => c.id == clienteIdValido)
          .firstOrNull;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nomesItensSemProduto.isEmpty
              ? 'Orcamento ${selecionado.numeroOrcamento} carregado com ${drafts.length} item(ns) para edicao.'
              : 'Orcamento ${selecionado.numeroOrcamento} carregado com ${drafts.length} item(ns). ${nomesItensSemProduto.length} item(ns) sem produto cadastrado foram ignorados.',
        ),
      ),
    );
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
    return linhas
        .map(
          (l) =>
              '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join('; ');
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

  Future<Uint8List> _gerarOrcamentoPdfBytes(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    final empresa = await widget.appConfigRepository.carregarEmpresaConfig();
    final logoBytes = empresa.logoPath.trim().isNotEmpty
        ? await File(
            empresa.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final doc = pw.Document();
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
    final layout = empresa.layoutImpressao.orcamento;
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
    );
    final unidadesItens = CupomPdfLayout.unidadesAlturaItensTermico(
      venda.itens.map((i) => i.nomeProduto),
    );

    doc.addPage(
      pw.Page(
        pageFormat: CupomPdfLayout.formatoPagina(
          modelo,
          linhasTexto: linhasTexto,
          qtdItens: unidadesItens > 0 ? unidadesItens : venda.itens.length,
          linhasExtras: linhasExtras,
          comLogo: comLogo,
        ),
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
                  'Validade do orcamento: $validadeFmt ($_validadeOrcamentoDias dias)',
                  layout,
                  fontWeight: pw.FontWeight.bold,
                ),
              CupomPdfLayout.divisoriaSecao(layout: layout),
              CupomPdfLayout.tituloSecao('ITENS', layout),
              if (CupomPdfLayout.cabecalhoColunasItens(layout) != null)
                CupomPdfLayout.cabecalhoColunasItens(layout)!,
              ...venda.itens.map(
                (item) => CupomPdfLayout.itemVenda(
                  layout: layout,
                  nomeProduto: item.nomeProduto,
                  quantidade: item.quantidade,
                  precoUnitario: item.precoUnitario,
                  subtotal: item.subtotal,
                  formatarMoeda: _formatarMoeda,
                ),
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
              CupomPdfLayout.textoCorpo(
                'Este orcamento e valido por $_validadeOrcamentoDias dias a partir da data de emissao.',
                layout,
                fontSize: layout.tamanhoFonteCorpo.fontSizeContato,
              ),
              CupomPdfLayout.espacoBloco(layout),
              ...CupomPdfLayout.rodapeDocumento(
                layout: layout,
                textoRodape: empresa.rodapeOrcamento,
              ),
              pw.SizedBox(height: CupomPdfLayout.feedCorteMm * PdfPageFormat.mm),
            ],
          );
        },
      ),
    );
    return doc.save();
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

  Future<void> _mostrarAcoesPdfOrcamento(Venda venda) async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                Navigator.pop(context, 'pdf'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                Navigator.pop(context, 'direto'),
            const SingleActivator(LogicalKeyboardKey.digit4): () =>
                Navigator.pop(context, 'imprimir'),
            const SingleActivator(LogicalKeyboardKey.numpad1): () =>
                Navigator.pop(context, 'fechar'),
            const SingleActivator(LogicalKeyboardKey.numpad2): () =>
                Navigator.pop(context, 'pdf'),
            const SingleActivator(LogicalKeyboardKey.numpad3): () =>
                Navigator.pop(context, 'direto'),
            const SingleActivator(LogicalKeyboardKey.numpad4): () =>
                Navigator.pop(context, 'imprimir'),
          },
          child: AlertDialog(
            title: const Text('Orcamento salvo'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deseja imprimir o orcamento ou mandar em PDF?'),
                SizedBox(height: 10),
                Text(
                  'Teclado: Esc ou 1 — fechar · 2 — PDF · 3 — impressao direta · '
                  '4 — acao Imprimir (Enter confirma o botao em foco) · Tab entre botoes',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'fechar'),
                child: const Text('Fechar (Esc · 1)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Mandar em PDF (2)'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'direto'),
                icon: const Icon(Icons.print),
                label: const Text('Impressao direta (3)'),
              ),
              ElevatedButton.icon(
                autofocus: true,
                onPressed: () => Navigator.pop(context, 'imprimir'),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimir (4 · Enter)'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarOrcamentoPdfBytes(venda);
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
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
          onLayout: (_) async => pdfBytes,
          name: 'Orcamento ${venda.numeroOrcamento}',
          format: config.modeloPdf == 'a4'
              ? PdfPageFormat.a4
              : PdfPageFormat(
                  CupomPdfLayout.larguraBobinaMm * PdfPageFormat.mm,
                  280 * PdfPageFormat.mm,
                ),
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName: 'orcamento_${venda.numeroOrcamento}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF do orcamento salvo em: $path')),
      );
    } catch (e) {
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

  /// Valor maximo de desconto em reais permitido neste pedido (config % x subtotal).
  double _valorMaximoDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    final sub = _totalOrcamento;
    return (sub * _maxDescontoPercentualPdv / 100).clamp(0.0, sub);
  }

  double _percentualDigitadoPdV() {
    if (_tipoDescontoPdV != 'percentual') return 0;
    final bruto = _percentualDigitadoBrutoSemLimitePdV();
    if (bruto == null) return 0;
    return bruto.clamp(0.0, _maxDescontoPercentualPdv);
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
    final maxPct = _maxDescontoPercentualPdv;
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

  String _mensagemErroDescontoPdVUltrapassaTeto() {
    final maxPct = _maxDescontoPercentualPdv;
    final maxReais = _valorMaximoDescontoReaisPdV();
    return 'Acima do permitido. Maximo: ${maxPct.toStringAsFixed(1)}% '
        'do subtotal = ${_formatarMoeda(maxReais)}.';
  }

  /// Desconto apenas sobre o subtotal; frete entra inteiro no total a pagar.
  double _valorDescontoReaisPdV() {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    final sub = _totalOrcamento;
    if (sub <= 0) return 0;
    final maxReais = _valorMaximoDescontoReaisPdV();
    if (_tipoDescontoPdV == 'percentual') {
      final pct = _percentualDigitadoPdV();
      return (sub * pct / 100).clamp(0.0, maxReais);
    }
    final digitado = _parseValorMonetario(_descontoPdVController.text);
    return digitado.clamp(0.0, maxReais).clamp(0.0, sub);
  }

  double _percentualEfetivoSobreSubtotalPdV() {
    final sub = _totalOrcamento;
    if (sub <= 0.004) return 0;
    return _valorDescontoReaisPdV() / sub * 100;
  }

  double _totalLiquidoPagamentoPdV() =>
      (_totalGeralComFrete - _valorDescontoReaisPdV()).clamp(
        0.0,
        double.infinity,
      );

  String _rotuloParcela(int parcelas) {
    if (parcelas <= 0) {
      return '1x';
    }
    final valorParcela = _totalLiquidoPagamentoPdV() / parcelas;
    return '${parcelas}x de ${_formatarMoeda(valorParcela)}';
  }

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
                  setState(() => _precoListaAtivo = intent.precoTipo);
                  return null;
                },
              ),
          SelecionarEntregaPadraoIntent:
              CallbackAction<SelecionarEntregaPadraoIntent>(
                onInvoke: (intent) {
                  setState(() => _tipoEntregaSelecionada = intent.tipoEntrega);
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
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Ponto de Venda'),
            actions: [
              _buildBotaoPrecoListaAppBar(),
              _buildBotaoEntregaPadraoAppBar(),
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
                _PdvHeaderPesquisa(
                  modoBarraCarrinho: true,
                  pesquisaFocus: _pesquisaFocus,
                  pesquisaController: _pesquisaController,
                  mostrarAjudaAtalhos: _mostrarAjudaAtalhos,
                  precoListaRotulo: _rotuloPreco(_precoListaAtivo),
                  onLimparBusca: _limparPesquisaAtalho,
                  onAbrirConsulta: () => unawaited(_abrirConsultaProdutos()),
                  onRecarregarProdutos: _carregarDadosIniciais,
                  onToggleAjudaAtalhos: () {
                    setState(() {
                      _mostrarAjudaAtalhos = !_mostrarAjudaAtalhos;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _PdvPainelCheckout(
                    leiauteEmpilhado: true,
                    keyPainel: _keyPainelCheckoutPdV,
                    painelCheckoutRecolhido: false,
                    carrinhoCount: _carrinho.length,
                    totalResumoColapsado: _formatarMoeda(_totalGeralComFrete),
                    onExpandirPainel: _irParaPesquisaProdutos,
                    orcamentoEmEdicao: _orcamentoEmEdicaoId != null,
                    orcamentoEmEdicaoNumero:
                        _orcamentoEmEdicaoNumero?.toString(),
                    onCancelarEdicaoOrcamento: () {
                      setState(() {
                        _orcamentoEmEdicaoId = null;
                        _orcamentoEmEdicaoNumero = null;
                      });
                    },
                    mostrarDicaAtalhosCarrinho:
                        _mostrarAjudaAtalhos && _carrinho.isNotEmpty,
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
                      onIrPesquisaQuandoVazio: () =>
                          unawaited(_abrirConsultaProdutos()),
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

/// Barra de pesquisa no topo do carrinho (Enter abre consulta em tela cheia).
class _PdvHeaderPesquisa extends StatelessWidget {
  const _PdvHeaderPesquisa({
    required this.modoBarraCarrinho,
    required this.pesquisaFocus,
    required this.pesquisaController,
    required this.mostrarAjudaAtalhos,
    required this.precoListaRotulo,
    required this.onLimparBusca,
    required this.onAbrirConsulta,
    required this.onRecarregarProdutos,
    required this.onToggleAjudaAtalhos,
  });

  final bool modoBarraCarrinho;
  final FocusNode pesquisaFocus;
  final TextEditingController pesquisaController;
  final bool mostrarAjudaAtalhos;
  final String precoListaRotulo;
  final VoidCallback onLimparBusca;
  final VoidCallback onAbrirConsulta;
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
              autofocus: true,
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
                    ? 'Pesquisar · $precoListaRotulo · Enter/F4 consulta'
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
              onSubmitted: (_) => onAbrirConsulta(),
            ),
            if (!modoBarraCarrinho) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preco lista: $precoListaRotulo · Enter ou F4 consulta produtos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
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
                ],
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
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.75,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      'F1–F3 preco · Ctrl+F1–F3 entrega padrao (novos itens) · F4/Enter consulta · F5 recarrega · '
                      'F6 carrinho · F8 consulta (vazio) ou foco busca · E no item altera entrega · Ctrl+D dividir · '
                      'Ctrl+K limpa · Ctrl+O ler orcamento · F10 salvar · Na consulta: setas, Enter, Esc.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
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
    required this.onIrPesquisaQuandoVazio,
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
  final VoidCallback onIrPesquisaQuandoVazio;

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
              rotuloPreco: widget.rotuloPreco(item.precoTipo),
              precoUnitarioFormatado: widget.formatarMoeda(item.precoUnitario),
              subtotalFormatado: widget.formatarMoeda(item.subtotal),
              quantidade: item.quantidade,
              tipoEntregaItem: item.tipoEntregaItem,
              selecionado: selecionado,
              linhaImpar: index.isOdd,
              onTap: () => widget.onSelecionarLinha(index),
              onAlternarTipoEntrega: () => widget.onAlternarTipoEntrega(index),
              onDiminuir: () => widget.onAlterarQuantidade(index, -1),
              onAumentar: () => widget.onAlterarQuantidade(index, 1),
              onDividir: () => widget.onDividirLinha(index),
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
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'F6 foca aqui · F8 pesquisa · Ctrl+F1–F3 entrega padrao · E tipo do item · Ctrl+D dividir · ↑↓ qtd · Ctrl+↑↓ outro item · Del remove',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
    required this.quantidade,
    required this.precoTipo,
    required this.tipoEntregaItem,
  });
  final int quantidade;
  final String precoTipo;
  final String tipoEntregaItem;
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
      content: SizedBox(
        width: 400,
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
        content: SizedBox(
          width: 460,
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
    required this.produto,
    required this.precoTipoInicial,
    required this.tipoEntregaInicial,
    required this.precoUnitarioDe,
    required this.formatarMoeda,
  });

  final Produto produto;
  final String precoTipoInicial;
  final String tipoEntregaInicial;
  final double Function(String precoTipo) precoUnitarioDe;
  final String Function(double) formatarMoeda;

  @override
  State<_AdicionarAoOrcamentoDialog> createState() =>
      _AdicionarAoOrcamentoDialogState();
}

class _AdicionarAoOrcamentoDialogState
    extends State<_AdicionarAoOrcamentoDialog> {
  late String _precoTipo;
  late String _tipoEntrega;
  late final TextEditingController _qtdController;
  final _qtdFocus = FocusNode(debugLabel: 'pdvDialogQtd');

  @override
  void initState() {
    super.initState();
    _precoTipo = widget.precoTipoInicial;
    _tipoEntrega = EntregaVendaHelper.normalizarTipoItem(
      widget.tipoEntregaInicial,
    );
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
    final q = int.tryParse(_qtdController.text.trim());
    if (q == null || q <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma quantidade maior que zero.')),
      );
      return;
    }
    Navigator.of(context).pop(
      _AdicionarOrcamentoResult(
        quantidade: q,
        precoTipo: _precoTipo,
        tipoEntregaItem: _tipoEntrega,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final precoUnit = widget.precoUnitarioDe(_precoTipo);
    return AlertDialog(
      title: Text('Adicionar: ${widget.produto.nome}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 8),
            TextFormField(
              controller: _qtdController,
              focusNode: _qtdFocus,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _confirmar(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Preco: ${widget.formatarMoeda(precoUnit)}'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _confirmar, child: const Text('Adicionar')),
      ],
    );
  }
}

/// F1/F2/F3 alternam qual preco usa adicao rapida e Enter na lista.
class SelecionarPrecoListaIntent extends Intent {
  const SelecionarPrecoListaIntent(this.precoTipo);
  final String precoTipo;
}

/// Ctrl+F1/F2/F3 definem entrega padrao para novos itens (icone E altera cada linha).
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

class _OrcamentoItemDraft {
  _OrcamentoItemDraft({
    required this.produto,
    required this.quantidade,
    required this.precoTipo,
    required this.precoUnitario,
    this.tipoEntregaItem = EntregaVendaHelper.tipoRetirada,
  });

  final Produto produto;
  int quantidade;
  final String precoTipo;
  final double precoUnitario;
  String tipoEntregaItem;

  double get subtotal => quantidade * precoUnitario;
}

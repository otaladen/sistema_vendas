import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/caixa_sessao_api.dart';
import '../../data/api/cliente_api_repository.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/app_config_repository.dart';
import '../../data/objectbox.dart';
import '../../data/caixa_auditoria_repository.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/sync/caixa_local_refresh_hub.dart';
import '../../data/sync/caixa_status_hub.dart';
import '../../data/vale_credito_service.dart';
import '../../data/venda_repository.dart';
import '../../model/recebimento_fiado.dart';
import '../shell/main_menu_deps.dart';
import '../shell/app_shell_aba_visibilidade.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../domain/promocao_cadastro.dart';
import '../../domain/promocao_preco_result.dart';
import '../../domain/promocao_preco_service.dart';
import '../../domain/produto_embalagem.dart';
import '../../domain/quantidade_venda_util.dart';
import '../../domain/produto_limite_desconto_pdv.dart';
import '../../domain/fiscal/caixa_fiscal_acao_helper.dart';
import '../../domain/fiscal/cliente_fiscal_helper.dart';
import '../../domain/venda_documento_pos_caixa.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../config/focus_nfe_runtime.dart';
import '../../data/kit_orcamento_repository.dart';
import '../../data/produto_sugestao_venda_repository.dart';
import '../../domain/pdv_consulta_multi_deposito_util.dart';
import '../../domain/pdv_kit_orcamento_insercao.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../domain/pagamento_orcamento.dart';
import '../../domain/vale_credito.dart';
import '../../domain/leitura_parcial_caixa.dart';
import '../../domain/plano_fiado.dart';
import '../../domain/ultimas_vendas_finalizadas_ordenacao.dart';
import '../../model/caixa_sessao.dart';
import '../../model/cliente.dart';
import '../../data/promocao_repository.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import '../../services/auditoria_registrar.dart';
import '../../services/cupom_nao_fiscal_venda_pdf.dart';
import '../../domain/fiscal/abrir_danfe_focus.dart';
import '../../domain/fiscal/venda_nfce_obrigatoria_helper.dart';
import '../../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../fiscal/abrir_documento_fiscal.dart';
import '../../services/focus_nfe_service.dart';
import '../../services/nfce_reconciliacao_service.dart';
import '../../services/gaveta_esc_pos_service.dart';
import '../../services/print_service.dart';
import '../clientes_page.dart';
import '../cupom_venda_impressao_helper.dart';
import '../../services/esc_pos_cupom_builder.dart';
import '../segunda_via_cupom_autorizacao.dart';
import '../widgets/conta_sessao_app_bar_actions.dart';
import '../widgets/lan_api_feedback.dart';
import '../widgets/pdv_tipo_entrega_item.dart';
import '../widgets/quantidade_pdv_input_formatter.dart';
import '../widgets/receber_fiado_panel.dart';
import '../../services/recibo_movimento_caixa_pdf.dart';
import '../../services/recibo_recebimento_fiado_pdf.dart';
import '../fiscal/emitir_nfce_venda_flow.dart';
import '../fiscal/nfe_gerenciamento_page.dart';
import '../fiscal/pendencias_fiscais_page.dart';
import '../pdv_consulta_produtos_page.dart';
import '../pdv_desconto_autorizacao.dart';
import '../promocao_margem_autorizacao.dart';
import '../../model/usuario_sistema.dart';
import 'alterar_pagamento_caixa_dialog.dart';
import 'autorizacao_gerente_caixa.dart';
import 'caixa_desconto_dialog.dart';
import 'caixa_etapa.dart';
import 'caixa_feedback.dart';
import 'caixa_pos_venda_sessao.dart';
import 'caixa_ultimas_vendas_list.dart';
import 'widgets/caixa_cobranca_painel.dart';
import 'widgets/caixa_pos_venda_fiscal_painel.dart';
import '../vendas/cancelar_venda_ui.dart';
import 'widgets/caixa_importar_orcamento_field.dart';

class CaixaPage extends StatefulWidget {
  const CaixaPage({
    super.key,
    required this.clienteRepository,
    required this.produtoRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioLogado,
    required this.usuarioAtual,
    required this.podeCancelarVendas,
    required this.podeLeituraParcialCaixa,
    required this.podeVisualizarAuditoriaCaixa,
    required this.podeManutencaoAuditoriaCaixa,
    required this.onLogout,
  });

  final dynamic clienteRepository;
  final dynamic produtoRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;
  final String usuarioAtual;
  final bool podeCancelarVendas;
  final bool podeLeituraParcialCaixa;
  final bool podeVisualizarAuditoriaCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final VoidCallback onLogout;

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  static const String _kCaixaAuditoriaKey = 'caixa_auditoria_eventos_v1';

  dynamic _kitOrcamentoRepo;
  ProdutoSugestaoVendaRepository? _sugestaoVendaRepo;

  static String _prefsUltimoTrocoValor(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_valor_v1';

  static String _prefsUltimoTrocoNumero(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_numero_v1';

  static String _prefsUltimoTrocoVendaId(String terminalId) =>
      'caixa_${terminalId}_ultimo_troco_venda_id_v1';

  static const _prefsOrdenacaoUltimasVendas =
      'caixa_ultimas_vendas_ordenacao_v2';
  final _sessaoRepo = CaixaSessaoRepository();
  final NumberFormat _currency = NumberFormat('#,##0.00', 'pt_BR');
  List<Venda> _orcamentos = [];
  Venda? _selecionado;
  CaixaEtapa _etapaCaixa = CaixaEtapa.fila;
  final _valorRecebidoController = TextEditingController();
  final _valorRecebidoFocusNode = FocusNode();
  final ScrollController _itensScrollController = ScrollController();
  VoidCallback? _syncHubListener;
  late dynamic _usuarioRepository;
  PromocaoPrecoService? _promoPrecoCache;
  final _pesquisaProdutoConferenciaController = TextEditingController();
  final _pesquisaProdutoConferenciaFocus = FocusNode();
  final _focusAtalhosCaixa = FocusNode(debugLabel: 'caixaAtalhosGlobais');
  final List<int> _produtosRecentesConferencia = [];
  /// Padrao para novos itens na conferencia (Ctrl+F1/F2/F3 ou chips).
  String? _tipoEntregaNovoItemConferencia;
  GavetaEscPosService? _gavetaService;
  double? _valorRecebido;
  bool _posVendaProcessando = false;
  /// Trava anti-duplicacao na finalizacao (clique duplo / Enter repetido).
  bool _finalizandoVenda = false;
  /// Trava anti-duplicacao em sangria/suprimento (clique duplo).
  bool _movimentoCaixaEmAndamento = false;
  CaixaPosVendaSessao? _posVenda;
  int _nfcePendenteEmissaoQtd = 0;
  double _nfcePendenteEmissaoTotal = 0;
  bool _caixaAberto = false;
  String _operadorCaixa = '';
  DateTime? _aberturaCaixaEm;
  double _fundoTrocoAbertura = 0;
  double _totalSuprimentos = 0;
  double _totalSangrias = 0;
  double _limiteDivergenciaSemSupervisor = 20;
  bool _exigirAutorizacaoSegundaViaCupom = true;
  bool _permitirVendaSemEstoque = false;
  bool _mostrarDescontoCaixa = true;
  double _maxDescontoPercentualPdv = 15;
  final Map<int, double> _descontoPdvBasePorVendaId = {};
  int? _mistoPreparadoParaId;
  List<PagamentoOrcamentoLinha> _mistoLinhasModelo = [];
  final List<TextEditingController> _mistoValorControllers = [];
  final List<FocusNode> _mistoValorFocusNodes = [];
  String _terminalId = '';
  Map<String, CaixaSessao> _sessoesRede = const {};
  bool _pesquisaOrcamentoDialogAberta = false;
  /// Terminal leve: aderiu a sessao aberta em outro PC (um caixa por loja).
  bool _caixaAderidoRemoto = false;
  String _terminalSessaoAbertaId = '';
  /// Evita loop: load → hub → load (travava ao abrir a aba Caixa).
  bool _recarregandoSessaoCaixa = false;
  bool _umCaixaPorLojaRemoto = true;
  CaixaSessaoApi? _caixaApi;
  bool _documentoFiscalAutomaticoDisparado = false;
  bool _gestaoCaixaExpandida = false;
  bool _painelCobrancaAberto = false;
  int? _ultimoTrocoVendaId;
  int _ultimoTrocoNumeroOrcamento = 0;
  double _ultimoTrocoValor = 0;
  late final FocusNfeService _focusNfeService;
  NfceReconciliacaoService? _nfceReconciliacao;
  Timer? _timerReconciliacaoNfce;
  Timer? _debounceSyncOrcamentos;
  bool _abaCaixaVisivel = true;
  bool? _apiOnlineCaixa;
  UltimasVendasFinalizadasOrdenacao _ordenacaoUltimasVendas =
      UltimasVendasFinalizadasOrdenacao.padrao;
  bool _correcaoFinalizadaEmDisparada = false;
  bool _caixaFiscalNaoBloqueante = true;
  int _caixaLimiteOrcamentosPendentes = 120;
  final _importarOrcamentoController = TextEditingController();
  final _importarOrcamentoFocus = FocusNode(debugLabel: 'caixaImportarOrcamento');

  PromocaoPrecoService? get _promoPreco {
    try {
      final deps = MainMenuDeps.maybeOf(context);
      final promoApi = deps?.promocaoRepository;
      if (promoApi != null) {
        return _promoPrecoCache ??= PromocaoPrecoService(promoApi);
      }
      final ob = widget.produtoRepository.objectBox;
      if (ob is! ObjectBox) return null;
      return _promoPrecoCache ??= PromocaoPrecoService(PromocaoRepository(ob));
    } catch (_) {
      return null;
    }
  }

  /// Itens sem ToMany ObjectBox (terminal leve).
  List<ItemVenda> _itensVenda(Venda v) {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      return repo.itensDaVendaSafe(v);
    }
    try {
      final via = repo.listarItensPorVenda(v.id);
      if (via is List<ItemVenda> && via.isNotEmpty) return via;
      if (via is List) {
        final tipados = via.whereType<ItemVenda>().toList();
        if (tipados.isNotEmpty) return tipados;
      }
    } catch (_) {}
    try {
      return List<ItemVenda>.from(v.itens);
    } catch (_) {
      return const [];
    }
  }

  double _subtotalLinhaItem(ItemVenda item) {
    final qtd = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: _produtoDoItem(item),
      quantidadeArmazenada: item.quantidade,
    );
    return qtd * item.precoUnitario;
  }

  Produto? _produtoDoItem(ItemVenda item) {
    try {
      final ligado = item.produto.target;
      if (ligado != null) return ligado;
    } catch (_) {}
    final id = item.produto.targetId;
    if (id <= 0) return null;
    try {
      return widget.produtoRepository.obterPorId(id) as Produto?;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    try {
      final deps = MainMenuDeps.maybeOf(context);
      if (deps?.kitOrcamentoRepository != null) {
        _kitOrcamentoRepo = deps!.kitOrcamentoRepository;
      } else {
        final ob = widget.produtoRepository.objectBox;
        if (ob is ObjectBox) {
          _kitOrcamentoRepo = KitOrcamentoRepository(ob);
          _sugestaoVendaRepo = ProdutoSugestaoVendaRepository(ob);
        }
      }
      if (_sugestaoVendaRepo == null) {
        try {
          final ob = widget.produtoRepository.objectBox;
          if (ob is ObjectBox) {
            _sugestaoVendaRepo = ProdutoSugestaoVendaRepository(ob);
          }
        } catch (_) {}
      }
    } catch (_) {}
    _usuarioRepository = MainMenuDeps.resolverUsuarioRepository(context);
    _focusNfeService = FocusNfeService(config: criarFocusNfeConfigPadrao());
    if (widget.vendaRepository is VendaRepository) {
      _nfceReconciliacao = NfceReconciliacaoService(
        vendaRepository: widget.vendaRepository as VendaRepository,
        focusNfe: _focusNfeService,
      );
    }
    _carregarLimiteDivergenciaCaixa();
    _carregarSessaoCaixa();
    _carregarOrcamentos();
    _syncHubListener = () {
      if (!mounted) return;
      _debounceSyncOrcamentos?.cancel();
      _debounceSyncOrcamentos = Timer(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        _atualizarOrcamentosAposSync();
      });
    };
    SyncRefreshHub.instance.addListener(_syncHubListener!);
    LanApiEventHub.instance.addListener(_onApiEntityChanged);
    CaixaLocalRefreshHub.instance.addListener(_onCaixaLocalRefresh);
    unawaited(_carregarOrdenacaoUltimasVendas());
    if (widget.vendaRepository is VendaRepository) {
      unawaited(_reconciliarNfcePendentes(mostrarFeedback: false));
      _atualizarResumoNfcePendenteEmissao();
      _iniciarPollReconciliacaoNfce();
    } else if (widget.vendaRepository is VendaApiRepository) {
      unawaited(_hidratarPendenciasFiscaisTerminal());
      unawaited(_hidratarUltimasVendasTerminal());
    }
    HardwareKeyboard.instance.addHandler(_handlerTeclasHardwareCaixa);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAtalhosCaixa.requestFocus();
    });
  }

  void _onApiEntityChanged() {
    if (!mounted) return;
    final online = LanApiEventHub.instance.online;
    if (_apiOnlineCaixa != online) {
      _apiOnlineCaixa = online;
      setState(() {});
    }
    if (LanApiEventHub.instance.deveBloquearOperacoes) return;
    final ent = LanApiEventHub.instance.ultimaEntidade;
    if (ent == 'caixa_sessoes' || ent == 'caixa') {
      unawaited(_carregarSessaoCaixa());
      return;
    }
    if (ent != 'venda' && ent != 'nfe_saida' && ent != 'empresa_config') return;
    _debounceSyncOrcamentos?.cancel();
    _debounceSyncOrcamentos = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      unawaited(_atualizarOrcamentosViaApi());
      if (ent == 'venda' || ent == 'nfe_saida') {
        unawaited(_hidratarPendenciasFiscaisTerminal());
        unawaited(_hidratarUltimasVendasTerminal());
      }
    });
  }

  void _onCaixaLocalRefresh() {
    if (!mounted || _recarregandoSessaoCaixa) return;
    unawaited(_carregarSessaoCaixa());
  }

  Future<void> _atualizarOrcamentosViaApi() async {
    if (LanApiEventHub.instance.deveBloquearOperacoes) return;
    final api = widget.vendaRepository;
    if (api is! VendaApiRepository) return;
    try {
      await api.hidratarOrcamentos(limit: _caixaLimiteOrcamentosPendentes);
    } on LanApiException {
      return;
    }
    if (!mounted) return;
    _carregarOrcamentos();
  }

  void _iniciarPollReconciliacaoNfce() {
    if (!_abaCaixaVisivel) return;
    _timerReconciliacaoNfce?.cancel();
    _timerReconciliacaoNfce = Timer.periodic(
      const Duration(seconds: 90),
      (_) {
        if (!mounted || !AppShellAbaVisibilidade.leituraSemDependencia(context)) {
          return;
        }
        unawaited(_reconciliarNfcePendentes(mostrarFeedback: true));
      },
    );
  }

  void _pararPollReconciliacaoNfce() {
    _timerReconciliacaoNfce?.cancel();
    _timerReconciliacaoNfce = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = MainMenuDeps.maybeOf(context);
    _usuarioRepository = MainMenuDeps.resolverUsuarioRepository(context);
    final terminal = deps?.terminalLeve == true ||
        widget.vendaRepository is VendaApiRepository;
    final client = deps?.lanApiClient;
    final apiNova = (terminal && client != null && client.configurado)
        ? CaixaSessaoApi(client)
        : null;
    // initState carrega sessao antes da API existir — recarrega ao conectar.
    final apiMudou = (_caixaApi == null) != (apiNova == null);
    _caixaApi = apiNova;
    if (apiMudou && apiNova != null) {
      unawaited(_carregarSessaoCaixa());
      unawaited(_hidratarUltimasVendasTerminal());
    }

    final visivel = AppShellAbaVisibilidade.estaAtiva(context);
    if (visivel == _abaCaixaVisivel) return;
    _abaCaixaVisivel = visivel;
    if (visivel) {
      unawaited(_carregarSessaoCaixa());
      unawaited(_hidratarUltimasVendasTerminal());
      _iniciarPollReconciliacaoNfce();
    } else {
      _pararPollReconciliacaoNfce();
    }
  }

  Future<void> _reconciliarNfcePendentes({required bool mostrarFeedback}) async {
    try {
      _focusNfeService.validarConfiguracao();
    } catch (_) {
      return;
    }
    final lote = await _nfceReconciliacao?.reconsultarTodasPendentes();
    if (mounted) _atualizarResumoNfcePendenteEmissao();
    if (!mounted || !mostrarFeedback || lote == null || lote.autorizadas <= 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lote.autorizadas == 1
              ? 'NFC-e pendente autorizada na reconsulta.'
              : '${lote.autorizadas} NFC-e(s) autorizada(s) na reconsulta.',
        ),
      ),
    );
  }

  void _atualizarResumoNfcePendenteEmissao() {
    final lista = widget.vendaRepository.listarComNfcePendenteEmissao();
    if (!mounted) return;
    setState(() {
      _nfcePendenteEmissaoQtd = lista.length;
      _nfcePendenteEmissaoTotal = VendaNfceObrigatoriaHelper.somaTotal(lista);
    });
  }

  Future<void> _hidratarUltimasVendasTerminal() async {
    final repo = widget.vendaRepository;
    if (repo is! VendaApiRepository) return;
    try {
      await repo.hidratarVendasFinalizadas(limit: 40);
    } catch (e) {
      debugPrint('Caixa: hidratar vendas finalizadas: $e');
    }
    if (!mounted) return;
    _atualizarListaUltimasVendasFinalizadasCaixa();
  }

  Future<void> _hidratarPendenciasFiscaisTerminal() async {
    final repo = widget.vendaRepository;
    if (repo is! VendaApiRepository) return;
    try {
      await repo.hidratarPendenciasFiscais();
    } catch (e) {
      debugPrint('Caixa: pendencias fiscais terminal: $e');
    }
    if (!mounted) return;
    _atualizarResumoNfcePendenteEmissao();
    _atualizarListaUltimasVendasFinalizadasCaixa();
  }

  /// Apos cancelar/emitir NFC-e: atualiza lista, banner e cache local.
  Future<void> _aposMutacaoFiscalOuCancelamentoCaixa({int? vendaId}) async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      if (vendaId != null && vendaId > 0) {
        try {
          await repo.atualizarVendaFinalizadaNoCache(vendaId);
        } catch (_) {}
      }
      try {
        await repo.hidratarPendenciasFiscais();
      } catch (_) {}
    }
    if (!mounted) return;
    _atualizarResumoNfcePendenteEmissao();
    _atualizarListaUltimasVendasFinalizadasCaixa();
  }

  Future<void> _abrirPendenciasFiscaisCaixa() async {
    final usuario = await _usuarioLogadoCaixa();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PendenciasFiscaisPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          appConfigRepository: widget.appConfigRepository,
          usuarioLogado: usuario,
        ),
      ),
    );
    if (!mounted) return;
    _atualizarResumoNfcePendenteEmissao();
  }

  Widget _buildChipNfcePendenteEmissao(BuildContext context) {
    if (!_caixaAberto || _nfcePendenteEmissaoQtd <= 0) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
      label: Text(
        '$_nfcePendenteEmissaoQtd NFC-e · ${_formatarMoeda(_nfcePendenteEmissaoTotal)}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      backgroundColor: scheme.errorContainer.withValues(alpha: 0.85),
      side: BorderSide(color: scheme.error.withValues(alpha: 0.35)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () => unawaited(_abrirPendenciasFiscaisCaixa()),
    );
  }

  Widget _acaoIconeCaixa(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool destacar = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        style: destacar
            ? IconButton.styleFrom(
                backgroundColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
              )
            : null,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildToolbarOrcamentoAtivo(
    BuildContext context, {
    required Venda selecionado,
    required Cliente? clienteSelecionado,
    bool incluirBuscaProduto = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semCliente = clienteSelecionado == null;
    final semVendedor = _vendedorDaVenda(selecionado) == null;
    final numLabel = selecionado.numeroOrcamento > 0
        ? selecionado.numeroOrcamento
        : selecionado.id;

    return Material(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Orc. $numLabel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (selecionado.entregaPendente) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text(
                      'Ret. futura',
                      style: theme.textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
                const Spacer(),
                _acaoIconeCaixa(
                  context,
                  icon: Icons.search,
                  tooltip: 'Importar orcamento (F1)',
                  onPressed: _abrirPesquisaOrcamento,
                ),
                _acaoIconeCaixa(
                  context,
                  icon: Icons.arrow_back,
                  tooltip: 'Voltar a fila (Esc)',
                  onPressed: _voltarParaFila,
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    [
                      'Entrega: ${_textoEntregaCaixa(selecionado)}',
                      if (_vendaExigeDadosCarreto(selecionado))
                        'Frete: ${_formatarMoeda(selecionado.valorFrete)}',
                      'Cliente: ${clienteSelecionado?.nomeRazao ?? 'Sem cliente'}',
                      'Vendedor: ${_rotuloVendedorUmLinha(selecionado)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _acaoIconeCaixa(
                  context,
                  icon: Icons.person_add_alt_1_outlined,
                  tooltip: 'Vincular cliente (F4)',
                  onPressed: _vincularClienteAgora,
                  destacar: semCliente,
                ),
                if (semVendedor)
                  _acaoIconeCaixa(
                    context,
                    icon: Icons.badge_outlined,
                    tooltip: 'Vincular vendedor (F7)',
                    onPressed: () => unawaited(_vincularVendedorAgora()),
                    destacar: true,
                  ),
              ],
            ),
            if (incluirBuscaProduto) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pesquisaProdutoConferenciaController,
                      focusNode: _pesquisaProdutoConferenciaFocus,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Adicionar produto — Enter ou F5',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (v) => unawaited(
                        _abrirConsultaProdutoConferencia(termo: v),
                      ),
                    ),
                  ),
                  _acaoIconeCaixa(
                    context,
                    icon: Icons.add_shopping_cart_outlined,
                    tooltip: 'Buscar produto (F5)',
                    onPressed: () =>
                        unawaited(_abrirConsultaProdutoConferencia()),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRodapeConferenciaAcao(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
    required double descontoCaixa,
  }) {
    final total = _buildRodapeConferenciaPagamentoTotal(
      context,
      selecionado: selecionado,
      totalComDesconto: totalComDesconto,
      descontoPdvOrcamento: descontoPdvOrcamento,
      descontoCaixa: descontoCaixa,
    );
    final botao = SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.icon(
        onPressed: _acaoPrincipalConferencia,
        icon: Icon(
          _podeFinalizarDiretoNaConferencia(selecionado)
              ? Icons.check_circle_outline
              : Icons.payments_outlined,
          size: 20,
        ),
        label: Text(_rotuloBotaoPrincipalConferencia(selecionado)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                total,
                const SizedBox(height: 8),
                botao,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: total),
              const SizedBox(width: 12),
              SizedBox(width: 168, child: botao),
            ],
          );
        },
      ),
    );
  }

  Future<void> _carregarLimiteDivergenciaCaixa() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    setState(() {
      _limiteDivergenciaSemSupervisor = config.limiteDivergenciaCaixa;
      _exigirAutorizacaoSegundaViaCupom =
          config.exigirAutorizacaoSegundaViaCupom;
      _permitirVendaSemEstoque = config.permitirVendaSemEstoque;
      _mostrarDescontoCaixa = config.mostrarCampoDescontoCaixa;
      _maxDescontoPercentualPdv = config.maxDescontoPercentualPdv;
      _caixaFiscalNaoBloqueante = config.caixaFiscalNaoBloqueante;
      _caixaLimiteOrcamentosPendentes =
          config.caixaLimiteOrcamentosPendentes.clamp(20, 500);
    });
  }

  bool _descontoCaixaDisponivel() =>
      _mostrarDescontoCaixa && _maxDescontoPercentualPdv > 0.004;

  void _garantirBaseDescontoPdv(Venda v) {
    _descontoPdvBasePorVendaId.putIfAbsent(
      v.id,
      () => v.descontoImplicitoTotal,
    );
  }

  double _descontoPdvOrcamentoExibicao(Venda v) {
    _garantirBaseDescontoPdv(v);
    return _descontoPdvBasePorVendaId[v.id] ?? v.descontoImplicitoTotal;
  }

  double _descontoCaixaAplicado(Venda v) {
    _garantirBaseDescontoPdv(v);
    final base = _descontoPdvBasePorVendaId[v.id] ?? 0;
    return (v.descontoImplicitoTotal - base).clamp(0, double.infinity);
  }

  List<LinhaCalculoLimiteDescontoPdv> _linhasLimiteDescontoCaixa(Venda v) {
    final out = <LinhaCalculoLimiteDescontoPdv>[];
    for (final item in _itensVenda(v)) {
      final produto = _produtoDoItem(item);
      if (produto == null) continue;
      out.add(
        LinhaCalculoLimiteDescontoPdv(
          produto: produto,
          precoTipo: item.precoTipo,
          subtotal: _subtotalLinhaItem(item),
          promocaoId: item.promocaoId,
        ),
      );
    }
    return out;
  }

  double _valorMaximoDescontoTotalCaixa(Venda v) {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    return ProdutoLimiteDescontoPdv.valorMaximoDescontoReais(
      linhas: _linhasLimiteDescontoCaixa(v),
      tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
    );
  }

  double _percentualMaximoEfetivoDescontoCaixa(Venda v) =>
      ProdutoLimiteDescontoPdv.percentualEquivalenteSobreSubtotal(
        linhas: _linhasLimiteDescontoCaixa(v),
        tetoEmpresaOuUsuario: _maxDescontoPercentualPdv,
      );

  double _valorMaximoDescontoAdicionalCaixa(Venda v) {
    if (_maxDescontoPercentualPdv <= 0) return 0;
    final tetoTotal = _valorMaximoDescontoTotalCaixa(v);
    final ja = v.descontoImplicitoTotal;
    return (tetoTotal - ja).clamp(0, v.total).toDouble();
  }

  Future<UsuarioSistema> _usuarioLogadoCaixa() async {
    final lista = await _usuarioRepository.listarTodos(); // policy-allow: usuario logado caixa
    for (final u in lista) {
      if (u.login == widget.usuarioAtual) return u;
    }
    return UsuarioSistema(
      id: '0',
      nome: widget.usuarioAtual,
      login: widget.usuarioAtual,
      senha: '',
    );
  }

  Future<void> _abrirDescontoCaixa() async {
    if (!_descontoCaixaDisponivel()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Desconto no caixa desativado nas configuracoes da empresa.',
          ),
        ),
      );
      return;
    }
    final v = _selecionado;
    if (v == null) return;
    if (_etapaCaixa != CaixaEtapa.conferencia) {
      return;
    }

    final maxAdicional = _valorMaximoDescontoAdicionalCaixa(v);

    final pedido = await mostrarDialogoDescontoCaixa(
      context,
      totalAtual: v.total,
      descontoPdv: _descontoPdvOrcamentoExibicao(v),
      descontoCaixaAtual: _descontoCaixaAplicado(v),
      maximoAdicionalReais: maxAdicional,
      maximoPercentual: _percentualMaximoEfetivoDescontoCaixa(v),
      formatarMoeda: _formatarMoeda,
    );
    if (pedido == null || !mounted) return;

    var valor = pedido.valorReais;
    AutorizacaoDescontoResultado? authDesconto;
    if (valor > maxAdicional + 0.009) {
      final usuario = await _usuarioLogadoCaixa();
      if (!mounted) return;
      authDesconto = await solicitarAutorizacaoDescontoAcimaTetoPdv(
        context,
        _usuarioRepository,
        usuarioLogado: usuario,
        maximoPermitidoReais: maxAdicional,
        descontoSolicitadoReais: valor,
        formatarMoeda: _formatarMoeda,
      );
      if (authDesconto == null || !mounted) return;
    }

    valor = valor.clamp(0, v.total).toDouble();
    if (valor <= 0.009) return;

    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .aplicarDescontoNoOrcamentoRemoto(
          v.id,
          valor,
          gerenteLogin: authDesconto?.login,
          gerenteSenha: authDesconto?.senha,
          exigeGerente: authDesconto != null,
        );
      } else {
        widget.vendaRepository.aplicarDescontoNoOrcamento(v.id, valor);
      }
      await _registrarAuditoriaCaixa(
        'desconto_caixa',
        detalhes: {
          'vendaId': v.id,
          'numeroOrcamento': v.numeroOrcamento,
          'descontoReais': valor,
          'totalAnterior': v.total,
          'totalNovo': v.total - valor,
        },
      );
      if (!mounted) return;
      _carregarOrcamentos();
      if (_painelCobrancaAberto &&
          _caixaPrecisaValorRecebidoDinheiro(_selecionado!)) {
        _prepararRecebidoDinheiro(_totalComDesconto(_selecionado!));
      }
      if (_painelCobrancaAberto) {
        _focarEntradaPrincipalCaixa();
      }
      CaixaFeedback.sucesso(
        context,
        'Desconto de ${_formatarMoeda(valor)} aplicado.',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel aplicar desconto: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  /// Limpa selecao e campos apos finalizar venda — caixa pronto para o proximo orcamento.
  void _prepararCaixaPosProximaVenda() {
    _carregarOrcamentos();
    _disposeMistoEdicao();
    setState(() {
      _selecionado = null;
      _posVenda = null;
      _posVendaProcessando = false;
      _documentoFiscalAutomaticoDisparado = false;
      _painelCobrancaAberto = false;
      _etapaCaixa = CaixaEtapa.fila;
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _valorRecebidoFocusNode.unfocus();
    });
    _focarAtalhosCaixaSeFila();
    _atualizarResumoNfcePendenteEmissao();
  }

  Future<void> _selecionarOrcamentoParaConferencia(Venda venda) async {
    _garantirBaseDescontoPdv(venda);
    var alvo = venda;
    // Aguarda itens da API antes de montar a conferencia (ToMany nao funciona detached).
    if (widget.vendaRepository is VendaApiRepository) {
      await _garantirItensOrcamentoApi(alvo.id);
      if (!mounted) return;
      alvo = widget.vendaRepository.obterPorId(alvo.id) ?? alvo;
    }
    setState(() {
      _selecionado = alvo;
      _painelCobrancaAberto = false;
      _etapaCaixa = CaixaEtapa.conferencia;
      _prepararEdicaoMisto(alvo);
      _sincronizarRecebidoPdVComOrcamento();
    });
  }

  Future<void> _garantirItensOrcamentoApi(int vendaId) async {
    final repo = widget.vendaRepository;
    if (repo is! VendaApiRepository) return;
    try {
      final locais = repo.listarItensPorVenda(vendaId);
      if (locais.isNotEmpty) return;
      await repo.carregarItensRemoto(vendaId);
      if (!mounted) return;
      final atualizado = repo.obterPorId(vendaId);
      if (atualizado == null) return;
      if (_selecionado?.id == vendaId) {
        setState(() {
          _selecionado = atualizado;
          _prepararEdicaoMisto(atualizado);
          _sincronizarRecebidoPdVComOrcamento();
        });
      }
    } catch (_) {}
  }

  Future<void> _importarOrcamentoPorNumero(int numero) async {
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    // Garante status fresco (evita F1 bloqueado com sessao ativa na rede).
    await _carregarSessaoCaixa();
    if (!mounted) return;
    if (!_caixaAberto) {
      final abrir = await _perguntarAbrirCaixaParaContinuar();
      if (abrir != true) {
        if (mounted) {
          CaixaFeedback.erro(
            context,
            'Caixa fechado. Abra o caixa para importar orcamentos.',
          );
        }
        return;
      }
      await _abrirCaixa();
      if (!_caixaAberto || !mounted) {
        if (mounted) {
          CaixaFeedback.erro(
            context,
            'Nao foi possivel abrir o caixa. Verifique a sessao na rede.',
          );
        }
        return;
      }
    }
    Venda? venda =
        widget.vendaRepository.buscarOrcamentoPendentePorNumero(numero);
    if (venda == null && widget.vendaRepository is VendaApiRepository) {
      try {
        venda = await (widget.vendaRepository as VendaApiRepository)
            .buscarOrcamentoPendentePorNumeroRemoto(numero);
      } catch (e) {
        if (!mounted) return;
        CaixaFeedback.erro(
          context,
          'Falha ao buscar orcamento: ${LanApiFeedback.mensagem(e)}',
        );
        return;
      }
    }
    if (venda == null) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Orcamento $numero nao encontrado ou ja foi finalizado.',
      );
      return;
    }
    _importarOrcamentoController.clear();
    final completo =
        widget.vendaRepository.obterPorId(venda.id) ?? venda;
    unawaited(_selecionarOrcamentoParaConferencia(completo));
  }

  void _voltarParaFila() {
    _disposeMistoEdicao();
    setState(() {
      _selecionado = null;
      _painelCobrancaAberto = false;
      _etapaCaixa = CaixaEtapa.fila;
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _valorRecebidoFocusNode.unfocus();
    });
    _focarAtalhosCaixaSeFila();
  }

  bool _conferenciaAtivaComOrcamento() =>
      _selecionado != null && _etapaCaixa == CaixaEtapa.conferencia;

  bool _podeFinalizarDiretoNaConferencia(Venda v) {
    const diretas = {
      'pix',
      'cartao_credito',
      'cartao_debito',
      'transferencia',
    };
    return diretas.contains(v.formaPagamento);
  }

  bool _exigePainelCobranca(Venda v) =>
      v.formaPagamento == 'dinheiro' ||
      v.formaPagamento == 'misto' ||
      v.formaPagamento == 'fiado';

  String _rotuloBotaoPrincipalConferencia(Venda v) {
    if (_podeFinalizarDiretoNaConferencia(v)) {
      return 'Finalizar (Enter)';
    }
    return 'Receber (Enter)';
  }

  void _prepararRecebidoDinheiro(double total) {
    final texto = total.toStringAsFixed(2).replaceAll('.', ',');
    _valorRecebidoController.value = TextEditingValue(
      text: texto,
      selection: TextSelection(baseOffset: 0, extentOffset: texto.length),
    );
    _valorRecebido = total;
  }

  void _abrirPainelCobranca() {
    if (_selecionado == null) return;
    final v = _selecionado!;
    if (_caixaPrecisaValorRecebidoDinheiro(v)) {
      _prepararRecebidoDinheiro(_totalComDesconto(v));
    } else {
      _sincronizarRecebidoPdVComOrcamento();
    }
    setState(() => _painelCobrancaAberto = true);
    _focarEntradaPrincipalCaixa();
  }

  void _fecharPainelCobranca() {
    if (!_painelCobrancaAberto) return;
    setState(() => _painelCobrancaAberto = false);
    _focusAtalhosCaixa.requestFocus();
  }

  void _acaoPrincipalConferencia() {
    final v = _selecionado;
    if (v == null || _finalizandoVenda) return;
    if (_painelCobrancaAberto) {
      unawaited(_finalizarOrcamento(v));
      return;
    }
    if (_podeFinalizarDiretoNaConferencia(v)) {
      unawaited(_finalizarOrcamento(v));
      return;
    }
    if (_exigePainelCobranca(v)) {
      _abrirPainelCobranca();
      return;
    }
    unawaited(_finalizarOrcamento(v));
  }

  bool _deveExibirDialogResumoFinalizacao(Venda venda, double valorFiado) {
    if (venda.formaPagamento == 'misto') return true;
    if (valorFiado > 0.001) return true;
    return false;
  }

  bool _campoTextoComFoco() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _tratarTeclaCaixaWizard(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_atalhoCaixaAtivo()) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_etapaCaixa == CaixaEtapa.fiscal) {
        unawaited(_encerrarPosVendaFiscal());
        return KeyEventResult.handled;
      }
      if (_painelCobrancaAberto) {
        _fecharPainelCobranca();
        return KeyEventResult.handled;
      }
      if (_etapaCaixa != CaixaEtapa.fila) {
        _voltarParaFila();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_campoTextoComFoco()) {
        if (_painelCobrancaAberto && _selecionado != null) {
          final focus = FocusManager.instance.primaryFocus;
          if (focus == _pesquisaProdutoConferenciaFocus) {
            return KeyEventResult.ignored;
          }
          unawaited(_finalizarOrcamento(_selecionado!));
          return KeyEventResult.handled;
        }
        if (_etapaCaixa == CaixaEtapa.conferencia) {
          return KeyEventResult.ignored;
        }
      }
      if (_conferenciaAtivaComOrcamento()) {
        _acaoPrincipalConferencia();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _carregarOrcamentos() {
    unawaited(_recarregarSessaoRede());
    setState(() {
      _orcamentos = widget.vendaRepository.listarOrcamentosPendentes(
        limit: _caixaLimiteOrcamentosPendentes,
      );
      _aplicarSelecionadoAposListaOrcamentos();
    });
  }

  /// Sync de rede: atualiza a lista em memoria; so rebuilda a tela se houver
  /// orcamento aberto na conferencia (itens/totais podem ter mudado).
  void _atualizarOrcamentosAposSync() {
    unawaited(_recarregarSessaoRede());
    final novos = widget.vendaRepository.listarOrcamentosPendentes(
      limit: _caixaLimiteOrcamentosPendentes,
    );
    _orcamentos = novos;
    if (_selecionado == null) {
      // Fila sem selecao: dialog de pesquisa escuta o hub sozinho.
      return;
    }
    if (!mounted) return;
    setState(() => _aplicarSelecionadoAposListaOrcamentos());
  }

  void _aplicarSelecionadoAposListaOrcamentos() {
    if (_selecionado != null) {
      _selecionado = _orcamentos
          .where((v) => v.id == _selecionado!.id)
          .firstOrNull;
    }
    if (_selecionado == null) {
      _valorRecebidoController.clear();
      _valorRecebido = null;
      _valorRecebidoFocusNode.unfocus();
      _disposeMistoEdicao();
    } else if (_mistoPreparadoParaId != _selecionado!.id) {
      _prepararEdicaoMisto(_selecionado!);
      _sincronizarRecebidoPdVComOrcamento();
    }
  }

  bool _atalhoCaixaAtivo() {
    if (!mounted || _pesquisaOrcamentoDialogAberta) return false;
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  /// F1-F5 no Windows: Shortcuts so disparam com foco na arvore do Caixa
  /// (menu lateral ou lista sem foco bloqueava). Handler global corrige isso.
  bool _handlerTeclasHardwareCaixa(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (!_atalhoCaixaAtivo()) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f1) {
      unawaited(_abrirPesquisaOrcamento());
      return true;
    }
    if (key == LogicalKeyboardKey.f2) {
      unawaited(_abrirSegundaViaCupom());
      return true;
    }
    if (key == LogicalKeyboardKey.f3) {
      if (_caixaAberto) {
        unawaited(_abrirReceberFiado());
      }
      return true;
    }
    if (key == LogicalKeyboardKey.f4) {
      if (_conferenciaAtivaComOrcamento()) {
        _vincularClienteAgora();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      if (_etapaCaixa == CaixaEtapa.conferencia && _selecionado != null) {
        unawaited(_abrirConsultaProdutoConferencia());
      }
      return true;
    }
    if (key == LogicalKeyboardKey.f6) {
      if (_conferenciaAtivaComOrcamento()) {
        unawaited(_abrirDescontoCaixa());
      }
      return true;
    }
    if (key == LogicalKeyboardKey.f7) {
      if (_conferenciaAtivaComOrcamento() &&
          _vendedorDaVenda(_selecionado!) == null) {
        unawaited(_vincularVendedorAgora());
      }
      return true;
    }
    return false;
  }

  void _focarAtalhosCaixaSeFila() {
    if (!mounted || _etapaCaixa != CaixaEtapa.fila) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _etapaCaixa != CaixaEtapa.fila) return;
      if (_campoTextoComFoco()) return;
      _focusAtalhosCaixa.requestFocus();
    });
  }

  Future<void> _abrirPesquisaOrcamento() async {
    // Trava imediatamente: F1 dispara no handler global e no Shortcuts, e o
    // Windows ainda repete a tecla enquanto a sessao/API carrega. Sem isso
    // abrem dois dialogos empilhados — o de baixo fica na tela apos a escolha.
    if (_pesquisaOrcamentoDialogAberta) return;
    _pesquisaOrcamentoDialogAberta = true;
    Venda? selecionado;
    try {
      selecionado = await _abrirPesquisaOrcamentoInterno();
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pesquisaOrcamentoDialogAberta = false;
      });
    }
    if (selecionado == null || !mounted) return;
    unawaited(_selecionarOrcamentoParaConferencia(selecionado));
  }

  Future<Venda?> _abrirPesquisaOrcamentoInterno() async {
    await _carregarSessaoCaixa();
    if (!mounted) return null;
    if (!_caixaAberto) {
      final abrir = await _perguntarAbrirCaixaParaContinuar();
      if (abrir != true) {
        if (mounted) {
          CaixaFeedback.erro(
            context,
            'Caixa fechado. Abra o caixa para importar orcamentos.',
          );
        }
        return null;
      }
      await _abrirCaixa();
      if (!_caixaAberto || !mounted) {
        if (mounted) {
          CaixaFeedback.erro(
            context,
            'Nao foi possivel abrir o caixa. Verifique a sessao na rede.',
          );
        }
        return null;
      }
    }
    // Terminal: rehidrata orcamentos via API. Celular: pull do hub.
    if (widget.vendaRepository is VendaApiRepository) {
      try {
        await (widget.vendaRepository as VendaApiRepository).hidratarOrcamentos(
          limit: _caixaLimiteOrcamentosPendentes,
        );
      } catch (e) {
        if (!mounted) return null;
        CaixaFeedback.erro(
          context,
          'Falha ao carregar orcamentos: ${LanApiFeedback.mensagem(e)}',
        );
      }
    } else {
      await LanSyncScheduler.solicitarSyncCompleto();
    }
    if (!mounted) return null;
    _carregarOrcamentos();
    return showDialog<Venda>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => _DialogoPesquisaOrcamento(
        orcamentos: List<Venda>.from(_orcamentos),
        clienteDaVenda: _clienteDaVenda,
        rotuloVendedor: _rotuloVendedorUmLinha,
        formatarMoeda: _formatarMoeda,
        qtdItens: (orc) {
          try {
            final n = widget.vendaRepository.listarItensPorVenda(orc.id);
            if (n is List && n.isNotEmpty) return n.length;
          } catch (_) {}
          try {
            return orc.itens.length;
          } catch (_) {
            return 0;
          }
        },
        buscarPorNumero: (n) =>
            widget.vendaRepository.buscarOrcamentoPendentePorNumero(n),
        buscarPorNumeroRemoto:
            widget.vendaRepository is VendaApiRepository
            ? (n) => (widget.vendaRepository as VendaApiRepository)
                .buscarOrcamentoPendentePorNumeroRemoto(n)
            : null,
        recarregarLista: () => widget.vendaRepository.listarOrcamentosPendentes(
          limit: _caixaLimiteOrcamentosPendentes,
        ),
      ),
    );
  }

  /// No misto, foca o primeiro valor do painel de conferencia; em dinheiro puro, foca o campo de especie.
  void _focarEntradaPrincipalCaixa() {
    final selecionado = _selecionado;
    if (selecionado == null) return;
    if (selecionado.formaPagamento == 'misto' &&
        _mistoValorFocusNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mistoValorFocusNodes.first.requestFocus();
        }
      });
      return;
    }
    if (_caixaPrecisaValorRecebidoDinheiro(selecionado)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _valorRecebidoFocusNode.requestFocus();
        }
      });
    }
  }

  String _formatarMoeda(double valor) => 'R\$ ${_currency.format(valor)}';

  double? _parseValor(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) {
      return null;
    }
    return double.tryParse(normalizado);
  }

  Future<void> _carregarSessaoCaixa() async {
    if (_recarregandoSessaoCaixa) return;
    _recarregandoSessaoCaixa = true;
    try {
      await _carregarSessaoCaixaInterno();
    } finally {
      _recarregandoSessaoCaixa = false;
    }
  }

  Future<void> _carregarSessaoCaixaInterno() async {
    _terminalId = await _sessaoRepo.obterTerminalId();
    final api = _caixaApi;
    if (api != null) {
      try {
        // Preferencia: sessao-ativa (libera operacao multi vs um-caixa).
        final snap = await api.sessaoAtiva(terminalId: _terminalId);
        if (!mounted) return;
        _aplicarSnapshotCaixaRemoto(snap);
        await _carregarUltimoTrocoRegistrado();
        return;
      } catch (e) {
        debugPrint('Caixa sessao-ativa API: $e');
        try {
          final snap = await api.listar();
          if (!mounted) return;
          _aplicarSnapshotCaixaRemoto(snap);
          await _carregarUltimoTrocoRegistrado();
          return;
        } catch (e2) {
          debugPrint('Caixa sessao listar API: $e2');
        }
      }
    }
    await _recarregarSessaoRede();
    final s = await _sessaoRepo.carregarSessaoLocal();
    if (!mounted) return;
    // PC1 com um-caixa: se outro terminal abriu via API, SharedPreferences
    // local ja foi atualizado — aderir a qualquer sessao aberta na loja.
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    final todas = await _sessaoRepo.listarTodasSessoes();
    CaixaSessao? abertaLoja;
    for (final x in todas.values) {
      if (x.aberto) {
        abertaLoja = x;
        break;
      }
    }
    if (!mounted) return;
    if (config.umCaixaAbertoPorLoja &&
        abertaLoja != null &&
        abertaLoja.terminalId != _terminalId) {
      setState(() {
        _sessoesRede = todas;
        _umCaixaPorLojaRemoto = true;
        _caixaAberto = true;
        _caixaAderidoRemoto = true;
        _terminalSessaoAbertaId = abertaLoja!.terminalId;
        _operadorCaixa = abertaLoja.operador;
        _aberturaCaixaEm = abertaLoja.aberturaEm;
        _fundoTrocoAbertura = abertaLoja.fundoTroco;
        _totalSuprimentos = abertaLoja.suprimentos;
        _totalSangrias = abertaLoja.sangrias;
      });
    } else {
      setState(() {
        _sessoesRede = todas;
        _umCaixaPorLojaRemoto = config.umCaixaAbertoPorLoja;
        _caixaAberto = s.aberto;
        _caixaAderidoRemoto = false;
        _terminalSessaoAbertaId = s.aberto ? s.terminalId : '';
        _operadorCaixa = s.operador;
        _aberturaCaixaEm = s.aberturaEm;
        _fundoTrocoAbertura = s.fundoTroco;
        _totalSuprimentos = s.suprimentos;
        _totalSangrias = s.sangrias;
      });
    }
    // So atualiza KPI — nao notificar CaixaLocalRefreshHub (loop infinito).
    CaixaStatusHub.instance.publicarDasSessoes(todas);
    await _carregarUltimoTrocoRegistrado();
  }

  void _aplicarSnapshotCaixaRemoto(CaixaSessoesSnapshot snap) {
    CaixaSessao? aberta = snap.aberta;
    if (aberta == null || !aberta.aberto) {
      for (final s in snap.terminais.values) {
        if (s.aberto) {
          aberta = s;
          break;
        }
      }
    }
    final meu = _terminalId.isNotEmpty &&
        aberta != null &&
        aberta.aberto &&
        aberta.terminalId == _terminalId;
    final aderirUmCaixa = aberta != null &&
        aberta.aberto &&
        snap.umCaixaAbertoPorLoja;
    // sessao-ativa ja calcula operacaoLiberada; listar cai no meu/aderir.
    final liberar = snap.operacaoLiberada || meu || aderirUmCaixa;
    setState(() {
      _sessoesRede = snap.terminais;
      _umCaixaPorLojaRemoto = snap.umCaixaAbertoPorLoja;
      if (liberar && aberta != null) {
        _caixaAberto = true;
        _caixaAderidoRemoto = !meu;
        _terminalSessaoAbertaId = aberta.terminalId;
        _operadorCaixa = aberta.operador;
        _aberturaCaixaEm = aberta.aberturaEm;
        _fundoTrocoAbertura = aberta.fundoTroco;
        _totalSuprimentos = aberta.suprimentos;
        _totalSangrias = aberta.sangrias;
      } else {
        _caixaAberto = false;
        _caixaAderidoRemoto = false;
        _terminalSessaoAbertaId = '';
        _operadorCaixa = '';
        _aberturaCaixaEm = null;
        _fundoTrocoAbertura = 0;
        _totalSuprimentos = 0;
        _totalSangrias = 0;
      }
    });
    // KPI do Inicio: status da loja (qualquer sessao), nao so operacao local.
    final lojaAberta = snap.abertosCount > 0 ||
        (snap.aberta?.aberto == true) ||
        snap.terminais.values.any((s) => s.aberto);
    CaixaStatusHub.instance.publicar(
      aberto: lojaAberta,
      operador: aberta?.operador ?? '',
      terminalId: aberta?.terminalId ?? '',
    );
    // Nao chamar CaixaLocalRefreshHub aqui: este metodo e chamado pelo listener
    // do hub (loop infinito e freeze ao abrir a aba).
  }

  Future<void> _recarregarSessaoRede() async {
    final api = _caixaApi;
    if (api != null) {
      try {
        final snap = await api.listar();
        if (!mounted) return;
        setState(() {
          _sessoesRede = snap.terminais;
          _umCaixaPorLojaRemoto = snap.umCaixaAbertoPorLoja;
        });
        return;
      } catch (_) {}
    }
    final mapa = await _sessaoRepo.listarTodasSessoes();
    if (!mounted) return;
    setState(() => _sessoesRede = mapa);
  }

  Future<void> _salvarSessaoCaixa() async {
    if (_terminalId.isEmpty) {
      _terminalId = await _sessaoRepo.obterTerminalId();
    }
    final api = _caixaApi;
    if (api != null && _caixaAberto) {
      final tid = (_caixaAderidoRemoto && _terminalSessaoAbertaId.isNotEmpty)
          ? _terminalSessaoAbertaId
          : _terminalId;
      try {
        await api.atualizar(
          terminalId: tid,
          operador: _operadorCaixa,
          fundoTroco: _fundoTrocoAbertura,
        );
        await _recarregarSessaoRede();
        return;
      } on LanApiException catch (e) {
        debugPrint('Caixa atualizar API: $e');
        if (mounted) {
          LanApiFeedback.snackAviso(
            context,
            e,
            prefixo: 'Sincronizacao do caixa',
          );
        }
      } catch (e) {
        debugPrint('Caixa atualizar API: $e');
      }
    }
    await _sessaoRepo.salvarSessaoLocal(
      CaixaSessao(
        terminalId: _terminalId,
        aberto: _caixaAberto,
        operador: _operadorCaixa,
        aberturaEm: _aberturaCaixaEm,
        fundoTroco: _fundoTrocoAbertura,
        suprimentos: _totalSuprimentos,
        sangrias: _totalSangrias,
      ),
    );
    await _recarregarSessaoRede();
  }

  Future<void> _carregarUltimoTrocoRegistrado() async {
    if (_terminalId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final vendaId = prefs.getInt(_prefsUltimoTrocoVendaId(_terminalId));
    if (vendaId == null) return;
    if (!mounted) return;
    setState(() {
      _ultimoTrocoVendaId = vendaId;
      _ultimoTrocoNumeroOrcamento =
          prefs.getInt(_prefsUltimoTrocoNumero(_terminalId)) ?? 0;
      _ultimoTrocoValor =
          prefs.getDouble(_prefsUltimoTrocoValor(_terminalId)) ?? 0;
    });
  }

  Future<void> _registrarUltimoTrocoFinalizado({
    required int vendaId,
    required int numeroOrcamento,
    required double troco,
  }) async {
    if (!mounted) return;
    setState(() {
      _ultimoTrocoVendaId = vendaId;
      _ultimoTrocoNumeroOrcamento = numeroOrcamento;
      _ultimoTrocoValor = troco;
    });
    if (_terminalId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsUltimoTrocoVendaId(_terminalId), vendaId);
    await prefs.setInt(_prefsUltimoTrocoNumero(_terminalId), numeroOrcamento);
    await prefs.setDouble(_prefsUltimoTrocoValor(_terminalId), troco);
  }

  Future<void> _registrarAuditoriaCaixa(
    String evento, {
    Map<String, dynamic>? detalhes,
  }) async {
    final em = DateTime.now();
    final detalhesFinais = CaixaAuditoriaRepository.enriquecerDetalhes(
      evento: evento,
      em: em,
      operador: _operadorCaixa,
      detalhes: detalhes,
    );
    final clientApi = mounted
        ? MainMenuDeps.maybeOf(context)?.lanApiClient
        : null;
    final registro = <String, dynamic>{
      'em': em.toIso8601String(),
      'usuario': widget.usuarioAtual,
      'operadorCaixa': _operadorCaixa,
      'evento': evento,
      'detalhes': detalhesFinais,
    };
    _espelharAuditoriaNoLogCentral(evento, detalhesFinais);
    try {
      _repoAuditoriaCaixa().gravarObjectBox(
        em: em,
        evento: evento,
        usuario: widget.usuarioAtual,
        operadorCaixa: _operadorCaixa,
        detalhes: detalhesFinais,
      );
    } catch (e) {
      debugPrint('Caixa: falha ao gravar auditoria ObjectBox: $e');
    }
    // Terminal: so o log unificado do PC1. PC1: prefs local (fonte da API).
    if (clientApi != null &&
        clientApi.configurado &&
        widget.vendaRepository is VendaApiRepository) {
      try {
        await clientApi.registrarAuditoriaCaixa(
          evento: evento,
          usuario: widget.usuarioAtual,
          operadorCaixa: _operadorCaixa,
          detalhes: detalhesFinais,
          em: em,
        );
      } catch (e) {
        debugPrint('Caixa: falha ao gravar auditoria no servidor: $e');
      }
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCaixaAuditoriaKey);
      List<dynamic> lista = [];
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            lista = decoded;
          }
        } catch (_) {}
      }
      lista.add(registro);
      if (lista.length > 300) {
        lista = lista.sublist(lista.length - 300);
      }
      await prefs.setString(_kCaixaAuditoriaKey, jsonEncode(lista));
    } catch (e) {
      debugPrint('Caixa: falha ao gravar auditoria local: $e');
    }
  }

  ObjectBox? _objectBoxLocal() {
    try {
      final viaDeps = MainMenuDeps.maybeOf(context)?.objectBox;
      if (viaDeps != null) return viaDeps;
      final ob = widget.produtoRepository.objectBox;
      if (ob is ObjectBox) return ob;
    } catch (_) {}
    return null;
  }

  CaixaAuditoriaRepository _repoAuditoriaCaixa() =>
      CaixaAuditoriaRepository(db: _objectBoxLocal());

  void _espelharAuditoriaNoLogCentral(
    String evento,
    Map<String, dynamic> detalhes,
  ) {
    final operador = detalhes['operador']?.toString() ?? _operadorCaixa;
    final valor = CaixaAuditoriaRepository.valorDoEvento(evento, detalhes);
    switch (evento) {
      case 'fechamento_caixa':
        final dif = detalhes['diferencaTotal'];
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.fechamentoCaixa,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo:
              'Fechamento de caixa — operador $operador'
              ' — valor ${_formatarMoeda(valor)}'
              '${dif is num ? ' (dif. ${_formatarMoeda(dif.toDouble())})' : ''}',
          detalhes: detalhes,
        );
        break;
      case 'suprimento':
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.suprimentoCaixa,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo:
              'Suprimento — operador $operador — ${_formatarMoeda(valor)}',
          detalhes: detalhes,
        );
        break;
      case 'sangria':
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.sangriaCaixa,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo: 'Sangria — operador $operador — ${_formatarMoeda(valor)}',
          detalhes: detalhes,
        );
        break;
      case 'fechamento_negado_divergencia':
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.caixa,
          acao: AuditoriaAcao.fechamentoNegado,
          usuarioLogin: widget.usuarioAtual,
          entidade: 'caixa',
          resumo: 'Fechamento negado por divergencia',
          detalhes: detalhes,
        );
    }
  }

  Future<void> _salvarAuditoriaCaixa(List<Map<String, dynamic>> registros) async {
    if (_auditoriaViaServidor) {
      final client = MainMenuDeps.maybeOf(context)!.lanApiClient!;
      await client.substituirAuditoriaCaixa(registros);
      return;
    }
    await _repoAuditoriaCaixa().substituirTodos(registros);
  }

  bool get _auditoriaViaServidor =>
      widget.vendaRepository is VendaApiRepository &&
      (MainMenuDeps.maybeOf(context)?.lanApiClient?.configurado ?? false);

  Future<List<Map<String, dynamic>>> _carregarAuditoriaCaixa() async {
    if (_auditoriaViaServidor) {
      final client = MainMenuDeps.maybeOf(context)!.lanApiClient!;
      try {
        return await client.listarAuditoriaCaixa(limit: 500);
      } catch (e) {
        debugPrint('Caixa: auditoria remota: $e');
        return [];
      }
    }
    try {
      return await _repoAuditoriaCaixa().listarTodosComoMapas();
    } catch (e) {
      debugPrint('Caixa: auditoria local: $e');
      return [];
    }
  }

  Future<bool> _autorizarSupervisorSeNecessario(double diferencaTotal) async {
    if (diferencaTotal.abs() <= _limiteDivergenciaSemSupervisor) {
      return true;
    }
    final loginController = TextEditingController();
    final senhaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Autorizacao de supervisor'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Divergencia acima de ${_formatarMoeda(_limiteDivergenciaSemSupervisor)}. '
                    'Informe credenciais de supervisor/administrador.',
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: loginController,
                    decoration: const InputDecoration(labelText: 'Login'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autorizar'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      loginController.dispose();
      senhaController.dispose();
      return false;
    }
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    loginController.dispose();
    senhaController.dispose();
    final usuario = await _usuarioRepository.autenticar(login, senha);
    final autorizado = usuario != null && usuario.ativo && (usuario.admin || usuario.podeFinanceiro);
    if (!autorizado && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credenciais sem permissao de supervisor/financeiro.'),
        ),
      );
    }
    return autorizado;
  }

  Future<void> _abrirHistoricoAuditoria() async {
    var registros = await _carregarAuditoriaCaixa();
    if (!mounted) return;
    final dtFmt = DateFormat('dd/MM HH:mm:ss');
    await showDialog<void>(
      context: context,
      builder: (context) {
        String operadorFiltro = '';
        DateTime? inicioFiltro;
        DateTime? fimFiltro;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtrados = _filtrarRegistrosAuditoria(
              registros: registros,
              operadorFiltro: operadorFiltro,
              inicio: inicioFiltro,
              fim: fimFiltro,
            );
            final resumo = _resumoEventosAuditoria(filtrados);
            return AlertDialog(
              title: const Text('Auditoria do caixa'),
              content: SizedBox(
                width: 860,
                height: 520,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Filtrar por operador/usuario',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                operadorFiltro = value.trim();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final data = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDate: inicioFiltro ?? DateTime.now(),
                            );
                            if (data == null) return;
                            setDialogState(() {
                              inicioFiltro = DateTime(data.year, data.month, data.day, 0, 0, 0);
                            });
                          },
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                            inicioFiltro == null
                                ? 'Inicio'
                                : DateFormat('dd/MM/yyyy').format(inicioFiltro!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final data = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDate: fimFiltro ?? DateTime.now(),
                            );
                            if (data == null) return;
                            setDialogState(() {
                              fimFiltro = DateTime(data.year, data.month, data.day, 23, 59, 59);
                            });
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            fimFiltro == null
                                ? 'Fim'
                                : DateFormat('dd/MM/yyyy').format(fimFiltro!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Limpar filtros',
                          onPressed: () {
                            setDialogState(() {
                              operadorFiltro = '';
                              inicioFiltro = null;
                              fimFiltro = null;
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        ),
                        if (widget.podeManutencaoAuditoriaCaixa)
                          IconButton(
                          tooltip: 'Manutencao da auditoria',
                          onPressed: () async {
                            final acao = await _abrirManutencaoAuditoriaDialog(
                              filtradosCount: filtrados.length,
                            );
                            if (acao == null) return;
                            if (!context.mounted) return;
                            if (acao == 'older_60' || acao == 'older_90') {
                              final dias = acao == 'older_60' ? 60 : 90;
                              final limite = DateTime.now().subtract(Duration(days: dias));
                              final antes = registros.length;
                              registros = registros.where((item) {
                                final em = DateTime.tryParse((item['em'] ?? '').toString());
                                if (em == null) return false;
                                return !em.isBefore(limite);
                              }).toList();
                              await _salvarAuditoriaCaixa(registros);
                              if (!context.mounted) return;
                              setDialogState(() {});
                              final removidos = antes - registros.length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Manutencao concluida. $removidos registros removidos.'),
                                ),
                              );
                              return;
                            }
                            if (acao == 'filtered') {
                              if (filtrados.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Nao ha registros no filtro atual para remover.'),
                                  ),
                                );
                                return;
                              }
                              final idsFiltrados = filtrados
                                  .map((item) => (item['em'] ?? '').toString() + (item['evento'] ?? '').toString())
                                  .toSet();
                              final antes = registros.length;
                              registros = registros.where((item) {
                                final chave = (item['em'] ?? '').toString() + (item['evento'] ?? '').toString();
                                return !idsFiltrados.contains(chave);
                              }).toList();
                              await _salvarAuditoriaCaixa(registros);
                              if (!context.mounted) return;
                              setDialogState(() {});
                              final removidos = antes - registros.length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Registros filtrados removidos: $removidos.'),
                                ),
                              );
                              return;
                            }
                          },
                          icon: const Icon(Icons.build_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Text('Aberturas: ${resumo['aberturas'] ?? 0}'),
                          Text('Suprimentos: ${resumo['suprimentos'] ?? 0}'),
                          Text('Sangrias: ${resumo['sangrias'] ?? 0}'),
                          Text('Fechamentos: ${resumo['fechamentos'] ?? 0}'),
                          Text('Leituras parciais: ${resumo['leituras_parciais'] ?? 0}'),
                          Text('Negados: ${resumo['negados'] ?? 0}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(child: Text('Sem registros de auditoria.'))
                          : ListView.builder(
                              itemCount: filtrados.length,
                              itemBuilder: (context, index) {
                                final item = filtrados[filtrados.length - 1 - index];
                                final em = DateTime.tryParse((item['em'] ?? '').toString());
                                final emFmt = em == null ? '-' : dtFmt.format(em.toLocal());
                                final evento = (item['evento'] ?? '-').toString();
                                final usuario = (item['usuario'] ?? '-').toString();
                                final detalhes = item['detalhes'];
                                final detalhesTxt = detalhes is Map ? jsonEncode(detalhes) : '';
                                return ListTile(
                                  dense: true,
                                  title: Text('$emFmt | $evento'),
                                  subtitle: Text(
                                    'Usuario: $usuario${detalhesTxt.isEmpty ? '' : ' | $detalhesTxt'}',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () => _exportarAuditoriaCsv(filtrados),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exportar CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportarAuditoriaPdf(filtrados),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Exportar PDF'),
                ),
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
  }

  Future<String?> _abrirManutencaoAuditoriaDialog({
    required int filtradosCount,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Manutencao da auditoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Escolha uma acao para limpar registros antigos.'),
              const SizedBox(height: 10),
              Text('Registros no filtro atual: $filtradosCount'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'older_60'),
              child: const Text('Remover > 60 dias'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'older_90'),
              child: const Text('Remover > 90 dias'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'filtered'),
              child: const Text('Remover periodo filtrado'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _filtrarRegistrosAuditoria({
    required List<Map<String, dynamic>> registros,
    required String operadorFiltro,
    required DateTime? inicio,
    required DateTime? fim,
  }) {
    final filtro = operadorFiltro.trim().toLowerCase();
    return registros.where((item) {
      final em = DateTime.tryParse((item['em'] ?? '').toString());
      if (inicio != null && (em == null || em.isBefore(inicio))) return false;
      if (fim != null && (em == null || em.isAfter(fim))) return false;
      if (filtro.isNotEmpty) {
        final usuario = (item['usuario'] ?? '').toString().toLowerCase();
        final operador = (item['operadorCaixa'] ?? '').toString().toLowerCase();
        if (!usuario.contains(filtro) && !operador.contains(filtro)) return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> _resumoEventosAuditoria(List<Map<String, dynamic>> registros) {
    int contar(String evento) =>
        registros.where((r) => (r['evento'] ?? '').toString() == evento).length;
    return {
      'aberturas': contar('abertura_caixa'),
      'suprimentos': contar('suprimento'),
      'sangrias': contar('sangria'),
      'fechamentos': contar('fechamento_caixa'),
      'leituras_parciais': contar('leitura_parcial_caixa'),
      'negados': contar('fechamento_negado_divergencia'),
    };
  }

  Future<void> _exportarAuditoriaCsv(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha dados para exportar.')),
      );
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar auditoria em CSV',
      fileName: 'auditoria_caixa_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null) return;
    final buffer = StringBuffer();
    buffer.writeln('data_hora,evento,usuario,operador_caixa,detalhes');
    for (final item in registros) {
      String esc(String v) => '"${v.replaceAll('"', '""')}"';
      final em = (item['em'] ?? '').toString();
      final evento = (item['evento'] ?? '').toString();
      final usuario = (item['usuario'] ?? '').toString();
      final operador = (item['operadorCaixa'] ?? '').toString();
      final detalhes = item['detalhes'] is Map ? jsonEncode(item['detalhes']) : '';
      buffer.writeln(
        '${esc(em)},${esc(evento)},${esc(usuario)},${esc(operador)},${esc(detalhes)}',
      );
    }
    final arquivo = File(path.toLowerCase().endsWith('.csv') ? path : '$path.csv');
    await arquivo.writeAsString(buffer.toString(), encoding: utf8, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV salvo em: ${arquivo.path}')),
    );
  }

  Future<void> _exportarAuditoriaPdf(List<Map<String, dynamic>> registros) async {
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao ha dados para exportar.')),
      );
      return;
    }
    final doc = pw.Document();
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return [
            pw.Text(
              'Auditoria do Caixa',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            ...registros.map((item) {
              final em = DateTime.tryParse((item['em'] ?? '').toString());
              final emFmt = em == null ? '-' : dtFmt.format(em.toLocal());
              final evento = (item['evento'] ?? '-').toString();
              final usuario = (item['usuario'] ?? '-').toString();
              final detalhes = item['detalhes'] is Map ? jsonEncode(item['detalhes']) : '';
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '$emFmt | $evento | usuario: $usuario${detalhes.isEmpty ? '' : ' | $detalhes'}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              );
            }),
          ];
        },
      ),
    );
    final path = await _escolherSalvarPdf(
      bytes: await doc.save(),
      suggestedFileName:
          'auditoria_caixa_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
    );
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF salvo em: $path')),
    );
  }

  Future<void> _abrirCaixa() async {
    if (_caixaAberto) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('O caixa ja esta aberto.')));
      return;
    }
    if (_terminalId.isEmpty) {
      _terminalId = await _sessaoRepo.obterTerminalId();
    }

    // Terminal: consulta servidor antes de abrir.
    final api = _caixaApi;
    if (api != null) {
      try {
        final snap = await api.listar();
        if (!mounted) return;
        if (snap.aberta != null && snap.aberta!.aberto) {
          if (snap.umCaixaAbertoPorLoja) {
            _aplicarSnapshotCaixaRemoto(snap);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Caixa ja aberto em ${snap.aberta!.terminalId}'
                  '${snap.aberta!.operador.trim().isNotEmpty ? ' (${snap.aberta!.operador})' : ''}. '
                  'Este terminal aderiu a sessao da loja.',
                ),
              ),
            );
            return;
          }
        }
      } catch (_) {}
    } else {
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      if (config.umCaixaAbertoPorLoja) {
        final outra =
            await CaixaSessaoRepository().obterSessaoAbertaEmOutroTerminal();
        if (outra != null && mounted) {
          final todas = await _sessaoRepo.listarTodasSessoes();
          if (!mounted) return;
          setState(() {
            _sessoesRede = todas;
            _umCaixaPorLojaRemoto = true;
            _caixaAberto = true;
            _caixaAderidoRemoto = true;
            _terminalSessaoAbertaId = outra.terminalId;
            _operadorCaixa = outra.operador;
            _aberturaCaixaEm = outra.aberturaEm;
            _fundoTrocoAbertura = outra.fundoTroco;
            _totalSuprimentos = outra.suprimentos;
            _totalSangrias = outra.sangrias;
          });
          CaixaStatusHub.instance.publicarDasSessoes(todas);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Caixa ja aberto em ${outra.terminalId}'
                '${outra.operador.trim().isNotEmpty ? ' (${outra.operador})' : ''}. '
                'Este terminal aderiu a sessao da loja.',
              ),
            ),
          );
          return;
        }
      }
    }

    final operadorController = TextEditingController(text: widget.usuarioAtual);
    final fundoController = TextEditingController(text: '0,00');
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Abrir caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: operadorController,
                    decoration: const InputDecoration(labelText: 'Operador responsavel'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fundoController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Fundo de troco inicial',
                      hintText: 'Ex.: 150,00',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir caixa'),
            ),
          ],
        );
      },
    );
    if (confirmar != true) {
      operadorController.dispose();
      fundoController.dispose();
      return;
    }
    if (!mounted) {
      operadorController.dispose();
      fundoController.dispose();
      return;
    }
    final operador = operadorController.text.trim();
    final fundo = _parseValor(fundoController.text) ?? 0;
    operadorController.dispose();
    fundoController.dispose();
    if (operador.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o operador para abrir o caixa.')),
      );
      return;
    }

    if (api != null) {
      try {
        final r = await api.abrir(
          terminalId: _terminalId,
          operador: operador,
          fundoTroco: fundo,
        );
        if (!mounted) return;
        if (!r.ok) {
          if (r.errorCode == 'caixa_ja_aberto' && r.sessaoAbertaConflito != null) {
            await _carregarSessaoCaixa();
            if (!mounted) return;
            CaixaLocalRefreshHub.instance.notificar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  r.message ??
                      'Caixa ja aberto na loja. Sessao aderida automaticamente.',
                ),
              ),
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r.message ?? r.errorCode ?? 'Falha ao abrir caixa')),
          );
          return;
        }
        setState(() {
          _caixaAberto = true;
          _caixaAderidoRemoto = false;
          _terminalSessaoAbertaId = _terminalId;
          _operadorCaixa = operador;
          _aberturaCaixaEm = DateTime.now();
          _fundoTrocoAbertura = fundo;
          _totalSuprimentos = 0;
          _totalSangrias = 0;
          if (r.terminais.isNotEmpty) _sessoesRede = r.terminais;
        });
        if (r.terminais.isNotEmpty) {
          CaixaStatusHub.instance.publicarDasSessoes(r.terminais);
        } else {
          CaixaStatusHub.instance.publicar(
            aberto: true,
            operador: operador,
            terminalId: _terminalId,
          );
        }
        // Terminal: API grava no servidor; avisa o Inicio neste PC tambem.
        CaixaLocalRefreshHub.instance.notificar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao abrir caixa no servidor: $e')),
        );
        return;
      }
    } else {
      setState(() {
        _caixaAberto = true;
        _caixaAderidoRemoto = false;
        _terminalSessaoAbertaId = _terminalId;
        _operadorCaixa = operador;
        _aberturaCaixaEm = DateTime.now();
        _fundoTrocoAbertura = fundo;
        _totalSuprimentos = 0;
        _totalSangrias = 0;
      });
      await _salvarSessaoCaixa();
      CaixaStatusHub.instance.publicar(
        aberto: true,
        operador: operador,
        terminalId: _terminalId,
      );
      CaixaLocalRefreshHub.instance.notificar();
    }

    await _registrarAuditoriaCaixa(
      'abertura_caixa',
      detalhes: {
        'operador': operador,
        'fundoTroco': _fundoTrocoAbertura,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Caixa aberto por $operador com fundo ${_formatarMoeda(_fundoTrocoAbertura)}.',
        ),
      ),
    );
  }

  String _terminalIdParaSessaoCaixa() {
    if (_caixaAderidoRemoto && _terminalSessaoAbertaId.isNotEmpty) {
      return _terminalSessaoAbertaId;
    }
    return _terminalId;
  }

  Future<CaixaSessao> _registrarMovimentacaoAtomica({
    required bool suprimento,
    required double valor,
  }) async {
    final api = _caixaApi;
    if (api != null) {
      final r = await api.registrarMovimentacao(
        terminalId: _terminalIdParaSessaoCaixa(),
        tipo: suprimento ? 'suprimento' : 'sangria',
        valor: valor,
      );
      if (!r.ok || r.sessao == null) {
        throw StateError(
          r.message ?? r.errorCode ?? 'Falha ao registrar movimentacao.',
        );
      }
      return r.sessao!;
    }
    if (_terminalId.isEmpty) {
      _terminalId = await _sessaoRepo.obterTerminalId();
    }
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    return _sessaoRepo.registrarMovimentacao(
      terminalId: _terminalId,
      deltaSuprimento: suprimento ? valor : 0,
      deltaSangria: suprimento ? 0 : valor,
      umCaixaAbertoPorLoja: config.umCaixaAbertoPorLoja,
    );
  }

  Future<void> _registrarMovimentoCaixa({
    required bool suprimento,
  }) async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abra o caixa antes de registrar movimentos.')),
      );
      return;
    }
    if (_movimentoCaixaEmAndamento) return;
    setState(() => _movimentoCaixaEmAndamento = true);
    _ResultadoMovimentoCaixa? resultado;
    try {
      resultado = await showDialog<_ResultadoMovimentoCaixa>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _DialogoSangriaSuprimento(
            suprimento: suprimento,
            parseValor: _parseValor,
            registrar: (valor) => _registrarMovimentacaoAtomica(
              suprimento: suprimento,
              valor: valor,
            ),
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _movimentoCaixaEmAndamento = false);
      } else {
        _movimentoCaixaEmAndamento = false;
      }
    }
    if (resultado == null || !mounted) return;
    final valor = resultado.valor;
    final obs = resultado.observacao;
    final sessao = resultado.sessao;
    setState(() {
      _totalSuprimentos = sessao.suprimentos;
      _totalSangrias = sessao.sangrias;
      if (sessao.fundoTroco > 0) {
        _fundoTrocoAbertura = sessao.fundoTroco;
      }
    });
    await _recarregarSessaoRede();
    final dataHora = DateTime.now();
    await _registrarAuditoriaCaixa(
      suprimento ? 'suprimento' : 'sangria',
      detalhes: {
        'valor': valor,
        'observacao': obs,
        'em': dataHora.toIso8601String(),
        'operador': _operadorCaixa,
      },
    );
    if (!mounted) return;
    final tipo = suprimento ? 'Suprimento' : 'Sangria';
    final tipoArquivo = suprimento ? 'suprimento' : 'sangria';
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    CaixaFeedback.sucesso(context, '$tipo de ${_formatarMoeda(valor)} registrado.');
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Comprovante de $tipo',
      content: 'Deseja imprimir o comprovante desta $tipo?',
      suggestedFileName:
          '${tipoArquivo}_caixa_${DateFormat('yyyyMMdd_HHmmss').format(dataHora)}.pdf',
      gerarPdf: () async {
        final layout = config.layoutImpressao.cupom;
        final bytes = await ReciboMovimentoCaixaPdf.gerarBytes(
          suprimento: suprimento,
          valor: valor,
          observacao: obs,
          operadorCaixa: _operadorCaixa,
          terminalId: _terminalId,
          dataHora: dataHora,
          config: config,
          fundoInicial: _fundoTrocoAbertura,
          totalSuprimentos: _totalSuprimentos,
          totalSangrias: _totalSangrias,
        );
        return cupomPdfLegado(
          bytes: bytes,
          config: config,
          layout: layout,
          linhasTexto: 18,
        );
      },
    );
  }

  LeituraParcialCaixaSnapshot _montarLeituraParcialLocal() {
    final abertura = _aberturaCaixaEm;
    final agora = DateTime.now();
    final totais = widget.vendaRepository.totaisMeiosPagamentoVendasFinalizadas(
      inicio: abertura,
      fim: agora,
    );
    var recDinheiro = 0.0;
    var recPix = 0.0;
    var recDebito = 0.0;
    var recCredito = 0.0;
    var recTotal = 0.0;
    var recQtd = 0;
    if (abertura != null) {
      final lista = widget.vendaRepository.recebimentos.listarNoPeriodo(
        inicio: abertura,
        fim: agora,
      );
      recQtd = lista.length;
      for (final rec in lista) {
        recTotal += rec.valorTotal;
        switch (rec.formaPagamento) {
          case 'pix':
            recPix += rec.valorTotal;
            break;
          case 'cartao_debito':
            recDebito += rec.valorTotal;
            break;
          case 'cartao_credito':
            recCredito += rec.valorTotal;
            break;
          case 'dinheiro':
            recDinheiro += rec.valorTotal;
            break;
          default:
            break;
        }
      }
    }
    final resumo = widget.vendaRepository.resumoVendasFinalizadasNoPeriodo(
      inicio: abertura,
      fim: agora,
    );
    return LeituraParcialCaixaSnapshot.montar(
      fundoTroco: _fundoTrocoAbertura,
      suprimentos: _totalSuprimentos,
      sangrias: _totalSangrias,
      vendasDinheiro: totais.dinheiro,
      vendasPix: totais.pix,
      vendasDebito: totais.debito,
      vendasCredito: totais.credito,
      vendasVale: totais.vale,
      recDinheiro: recDinheiro,
      recPix: recPix,
      recDebito: recDebito,
      recCredito: recCredito,
      recTotal: recTotal,
      recQuantidade: recQtd,
      totalVendas: resumo.totalVendas,
      quantidadeVendas: resumo.quantidadeVendas,
      aberturaEm: abertura,
      operador: _operadorCaixa,
    );
  }

  Map<String, double> _totaisEsperadosFechamento() {
    final s = _montarLeituraParcialLocal();
    return {
      'dinheiro': s.dinheiroGaveta,
      'pix': s.pix,
      'debito': s.debito,
      'credito': s.credito,
    };
  }

  /// Terminal leve: totais reais do PC1 via `/api/caixa/leitura-parcial`.
  /// Nunca cai no stub local zerado quando o terminal usa a API.
  Future<Map<String, double>> _totaisEsperadosFechamentoAsync() async {
    if (_caixaApi != null || widget.vendaRepository is VendaApiRepository) {
      return _lerTotaisFechamentoDaApi();
    }
    return _totaisEsperadosFechamento();
  }

  bool _leituraParcialValida(Map<String, dynamic> data) =>
      LeituraParcialCaixaSnapshot.respostaValida(data);

  Future<Map<String, double>> _lerTotaisFechamentoDaApi() async {
    final deps = MainMenuDeps.maybeOf(context);
    final client = deps?.lanApiClient;
    if (client == null || !client.configurado) {
      throw StateError('sem_conexao_pc1');
    }
    final data = await client.leituraParcialCaixa(
      terminalId: _terminalIdParaSessaoCaixa(),
    );
    if (!_leituraParcialValida(data)) {
      throw StateError(
        data['error']?.toString().trim().isNotEmpty == true
            ? '${data['error']}'
            : 'leitura_parcial_invalida',
      );
    }
    return {
      'dinheiro': (data['dinheiroGaveta'] as num).toDouble(),
      'pix': (data['pix'] as num).toDouble(),
      'debito': (data['debito'] as num).toDouble(),
      'credito': (data['credito'] as num).toDouble(),
    };
  }

  Future<void> _abrirReceberFiado() async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abra o caixa antes de receber pagamentos de fiado.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Receber fiado'),
          content: SizedBox(
            width: 720,
            height: 520,
            child: ReceberFiadoPanel(
              vendaRepository: widget.vendaRepository,
              clienteRepository: widget.clienteRepository,
              onRecebimentoRegistrado: (resultado) {
                _aposRecebimentoFiadoNoCaixa(resultado);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _aposRecebimentoFiadoNoCaixa(
    RecebimentoFiadoResultado resultado,
  ) async {
    await _registrarAuditoriaCaixa(
      'recebimento_fiado',
      detalhes: {
        'recebimentoId': resultado.recebimentoId,
        'clienteId': resultado.cliente.id,
        'clienteNome': resultado.cliente.nomeRazao,
        'valor': resultado.valorTotal,
        'formaPagamento': resultado.formaPagamento,
      },
    );
    if (!mounted) return;

    final rotuloForma = _rotuloFormaPagamento(resultado.formaPagamento);
    final acaoRecibo = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Recebimento registrado'),
        content: Text(
          '${resultado.cliente.nomeRazao}\n'
          'Valor: ${_formatarMoeda(resultado.valorTotal)}\n'
          'Forma: $rotuloForma\n\n'
          'O valor entrou no fluxo do caixa (fechamento/leitura parcial).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'fechar'),
            child: const Text('Fechar'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'recibo'),
            icon: const Icon(Icons.receipt_outlined),
            label: const Text('Recibo (opcional)'),
          ),
        ],
      ),
    );
    if (!mounted || acaoRecibo != 'recibo') return;

    RecebimentoFiado? rec;
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        rec = await repo.obterRecebimentoRemoto(resultado.recebimentoId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Falha ao carregar recibo: ${LanApiFeedback.mensagem(e)}',
            ),
          ),
        );
        return;
      }
    } else {
      rec = repo.recebimentos.obterPorId(resultado.recebimentoId)
          as RecebimentoFiado?;
    }
    if (rec == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recebimento nao encontrado para emitir o recibo.'),
        ),
      );
      return;
    }
    final recebimento = rec;

    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;

    final saldoOverride = repo is VendaApiRepository
        ? repo.saldoRestanteAposRecebimento(resultado.recebimentoId)
        : null;

    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Recibo de pagamento (fiado)',
      content: 'Deseja imprimir o recibo para o cliente?',
      suggestedFileName:
          'recibo_fiado_${resultado.cliente.id}_${recebimento.id}.pdf',
      gerarPdf: () async {
        final layout = config.layoutImpressao.cupom;
        final bytes = await ReciboRecebimentoFiadoPdf.gerarBytes(
          recebimento: recebimento,
          cliente: resultado.cliente,
          vendaRepository: widget.vendaRepository,
          config: config,
          operadorCaixa: _operadorCaixa,
          saldoRestanteOverride: saldoOverride,
        );
        return cupomPdfLegado(
          bytes: bytes,
          config: config,
          layout: layout,
          linhasTexto: 20,
        );
      },
    );
  }

  String _formatarAberturaLeituraParcial(DateTime? abertura) {
    if (abertura == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(abertura.toLocal());
  }

  Future<void> _mostrarLeituraParcial() async {
    if (!widget.podeLeituraParcialCaixa) return;
    if (!_caixaAberto) {
      if (!mounted) return;
      CaixaFeedback.aviso(
        context,
        'Abra o caixa para consultar a leitura parcial.',
      );
      return;
    }

    final api = _caixaApi;
    if (api != null) {
      await _mostrarLeituraParcialRemota(api);
      return;
    }

    try {
      final snap = _montarLeituraParcialLocal();
      try {
        await _registrarAuditoriaCaixa(
          'leitura_parcial_caixa',
          detalhes: snap.toAuditoriaDetalhes(),
        );
      } catch (e) {
        debugPrint('Caixa: auditoria leitura parcial: $e');
      }
      if (!mounted) return;
      _exibirDialogLeituraParcial(snap);
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Erro ao consultar leitura parcial: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  Future<void> _mostrarLeituraParcialRemota(CaixaSessaoApi api) async {
    try {
      final deps = MainMenuDeps.maybeOf(context);
      final client = deps?.lanApiClient;
      if (client == null) {
        throw StateError('sem_conexao_pc1');
      }
      final data = await client.leituraParcialCaixa(
        terminalId: _terminalIdParaSessaoCaixa(),
      );
      if (!mounted) return;
      final snap = LeituraParcialCaixaSnapshot.fromJson(data);
      if (snap == null) {
        CaixaFeedback.aviso(
          context,
          data['error']?.toString().trim().isNotEmpty == true
              ? '${data['error']}'
              : 'Conexao com o servidor (PC1) oscilou. Tente novamente.',
        );
        return;
      }
      try {
        await _registrarAuditoriaCaixa(
          'leitura_parcial_caixa',
          detalhes: snap.toAuditoriaDetalhes(),
        );
      } catch (e) {
        debugPrint('Caixa: auditoria leitura parcial: $e');
      }
      if (!mounted) return;
      _exibirDialogLeituraParcial(snap);
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Erro ao consultar leitura parcial: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  void _exibirDialogLeituraParcial(LeituraParcialCaixaSnapshot snap) {
    final aberturaFmt = _formatarAberturaLeituraParcial(snap.aberturaEm);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Leitura parcial do caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Resumo desde a abertura ($aberturaFmt) ate agora, '
                    'sem fechar o caixa.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vendas finalizadas',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  Text('Quantidade: ${snap.quantidadeVendas}'),
                  Text(
                    'Total em vendas: ${_formatarMoeda(snap.totalVendas)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Recebimentos de fiado: ${snap.recebimentosFiadoQuantidade} '
                    '(${_formatarMoeda(snap.recebimentosFiadoTotal)})',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Recebimentos por forma de pagamento (esperado)',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  Text(
                    'Inclui vendas do periodo + quitacoes de fiado no caixa. '
                    'Vale nao entra na gaveta.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dinheiro na gaveta (fundo + vendas em dinheiro + '
                    'suprimentos - sangrias): '
                    '${_formatarMoeda(snap.dinheiroGaveta)}',
                  ),
                  Text('PIX: ${_formatarMoeda(snap.pix)}'),
                  Text('Cartao debito: ${_formatarMoeda(snap.debito)}'),
                  Text('Cartao credito: ${_formatarMoeda(snap.credito)}'),
                  if (snap.vale > 0.001)
                    Text(
                      'Vale de credito (nao entra na gaveta): '
                      '${_formatarMoeda(snap.vale)}',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Fundo inicial: ${_formatarMoeda(snap.fundoTroco)} | '
                    'Suprimentos: ${_formatarMoeda(snap.suprimentos)} | '
                    'Sangrias: ${_formatarMoeda(snap.sangrias)}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fecharCaixa() async {
    if (!_caixaAberto) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('O caixa ja esta fechado.')));
      return;
    }
    late final Map<String, double> esperados;
    try {
      esperados = await _totaisEsperadosFechamentoAsync();
    } catch (_) {
      if (!mounted) return;
      final tentar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conexao com o servidor oscilou'),
          content: const Text(
            'Nao foi possivel obter o saldo real do caixa no servidor (PC1). '
            'O fechamento foi bloqueado para evitar conferencia com valores zerados '
            'ou desatualizados.\n\n'
            'Verifique a conexao e tente novamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
      if (tentar == true && mounted) {
        await _fecharCaixa();
      }
      return;
    }
    if (!mounted) return;
    final dinheiroController = TextEditingController(text: '0,00');
    final pixController = TextEditingController(text: '0,00');
    final debitoController = TextEditingController(text: '0,00');
    final creditoController = TextEditingController(text: '0,00');
    final obsController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Fechamento de caixa'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLinhaConferenciaFechamento(
                    label: 'Dinheiro',
                    controller: dinheiroController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'PIX',
                    controller: pixController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'Cartao debito',
                    controller: debitoController,
                  ),
                  const SizedBox(height: 8),
                  _buildLinhaConferenciaFechamento(
                    label: 'Cartao credito',
                    controller: creditoController,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: obsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observacao de fechamento',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar fechamento'),
            ),
          ],
        );
      },
    );
    final declaradoDinheiro = _parseValor(dinheiroController.text) ?? 0;
    final declaradoPix = _parseValor(pixController.text) ?? 0;
    final declaradoDebito = _parseValor(debitoController.text) ?? 0;
    final declaradoCredito = _parseValor(creditoController.text) ?? 0;
    final obs = obsController.text.trim();
    dinheiroController.dispose();
    pixController.dispose();
    debitoController.dispose();
    creditoController.dispose();
    obsController.dispose();
    if (confirmar != true) return;
    final difDinheiro = declaradoDinheiro - (esperados['dinheiro'] ?? 0);
    final difPix = declaradoPix - (esperados['pix'] ?? 0);
    final difDebito = declaradoDebito - (esperados['debito'] ?? 0);
    final difCredito = declaradoCredito - (esperados['credito'] ?? 0);
    final difTotal = difDinheiro + difPix + difDebito + difCredito;
    final autorizado = await _autorizarSupervisorSeNecessario(difTotal);
    if (!autorizado) {
      await _registrarAuditoriaCaixa(
        'fechamento_negado_divergencia',
        detalhes: {
          'diferencaTotal': difTotal,
        },
      );
      return;
    }
    final operadorFechamento = _operadorCaixa;
    final aberturaFechamento = _aberturaCaixaEm;
    final fundoAbertura = _fundoTrocoAbertura;
    final suprimentos = _totalSuprimentos;
    final sangrias = _totalSangrias;
    final fechamentoEm = DateTime.now();
    final api = _caixaApi;
    // Capturar ANTES do setState — aderido limpa estes campos.
    final sessaoDonaId = _terminalSessaoAbertaId.isNotEmpty
        ? _terminalSessaoAbertaId
        : _terminalId;
    // Um-caixa ou aderido: sempre forca fechamento da sessao aberta na loja.
    // Evita sessao orfa quando o terminal local nao e o dono da sessao.
    final forcarRemoto = _caixaAderidoRemoto ||
        _umCaixaPorLojaRemoto ||
        (_terminalSessaoAbertaId.isNotEmpty &&
            _terminalSessaoAbertaId != _terminalId);
    if (forcarRemoto &&
        sessaoDonaId.isNotEmpty &&
        sessaoDonaId != _terminalId &&
        mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fechar caixa de outro terminal?'),
          content: Text(
            'A sessao esta aberta em $sessaoDonaId'
            '${_operadorCaixa.trim().isNotEmpty ? ' ($_operadorCaixa)' : ''}. '
            'Fechar daqui encerra o caixa da loja inteira.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fechar mesmo assim'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (api != null) {
      try {
        var r = await api.fechar(
          terminalId: _terminalId,
          forcar: forcarRemoto,
        );
        if (!mounted) return;
        if (!r.ok && r.errorCode == 'caixa_outro_terminal') {
          final ok2 = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirmar fechamento remoto'),
              content: Text(r.message ?? 'Fechar caixa aberto em outro PC?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
          if (ok2 != true) return;
          r = await api.fechar(terminalId: _terminalId, forcar: true);
        }
        if (!r.ok) {
          // Ultimo recurso: reset de orfaos no servidor.
          final resetar = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Desbloquear caixa?'),
              content: Text(
                '${r.message ?? 'Falha ao fechar a sessao.'}\n\n'
                'Deseja forcar o reset de todas as sessoes abertas no servidor?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Resetar sessoes'),
                ),
              ],
            ),
          );
          if (resetar == true) {
            final rr = await api.reset(motivo: 'fechamento_ui');
            if (!rr.ok && mounted) {
              CaixaFeedback.erro(
                context,
                rr.message ?? 'Falha ao resetar sessoes de caixa',
              );
              return;
            }
          } else {
            if (mounted) {
              CaixaFeedback.erro(
                context,
                r.message ?? 'Falha ao fechar caixa',
              );
            }
            return;
          }
        }
      } catch (e) {
        if (!mounted) return;
        CaixaFeedback.erro(
          context,
          'Falha ao fechar caixa no servidor: ${LanApiFeedback.mensagem(e)}',
        );
        return;
      }
    } else if (forcarRemoto) {
      // PC servidor aderido / um-caixa: fecha TODAS as sessoes (ex.: pc_localhost).
      await _sessaoRepo.fecharTodasSessoesAbertas(propagarRede: true);
    } else {
      await _sessaoRepo.salvarSessaoLocal(
        CaixaSessao(
          terminalId: sessaoDonaId.isNotEmpty ? sessaoDonaId : _terminalId,
          aberto: false,
          operador: '',
          fundoTroco: 0,
          suprimentos: 0,
          sangrias: 0,
          atualizadoEm: DateTime.now(),
        ),
        propagarRede: true,
      );
    }
    if (!mounted) return;
    setState(() {
      _caixaAberto = false;
      _caixaAderidoRemoto = false;
      _terminalSessaoAbertaId = '';
      _operadorCaixa = '';
      _aberturaCaixaEm = null;
      _fundoTrocoAbertura = 0;
      _totalSuprimentos = 0;
      _totalSangrias = 0;
    });
    CaixaStatusHub.instance.publicar(aberto: false);
    // Evita o load imediato reabrir UI como "aderido" antes do persist.
    if (api != null) {
      await _carregarSessaoCaixa();
      if (mounted && _caixaAberto) {
        // API fechou mas snapshot ainda veio aberto: forca UI fechada.
        setState(() {
          _caixaAberto = false;
          _caixaAderidoRemoto = false;
          _terminalSessaoAbertaId = '';
          _operadorCaixa = '';
          _aberturaCaixaEm = null;
          _fundoTrocoAbertura = 0;
          _totalSuprimentos = 0;
          _totalSangrias = 0;
        });
        CaixaStatusHub.instance.publicar(aberto: false);
      }
    }
    CaixaLocalRefreshHub.instance.notificar();
    await _registrarAuditoriaCaixa(
      'fechamento_caixa',
      detalhes: {
        'operador': operadorFechamento,
        'fundoTroco': fundoAbertura,
        'suprimentos': suprimentos,
        'sangrias': sangrias,
        'sessaoFechada': sessaoDonaId,
        'forcarLoja': forcarRemoto,
        'esperadoDinheiro': esperados['dinheiro'] ?? 0,
        'esperadoPix': esperados['pix'] ?? 0,
        'esperadoDebito': esperados['debito'] ?? 0,
        'esperadoCredito': esperados['credito'] ?? 0,
        'declaradoDinheiro': declaradoDinheiro,
        'declaradoPix': declaradoPix,
        'declaradoDebito': declaradoDebito,
        'declaradoCredito': declaradoCredito,
        'diferencaTotal': difTotal,
        'observacao': obs,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Caixa fechado. Diferenca total: ${_formatarMoeda(difTotal)}.'
          '${obs.isEmpty ? '' : ' Obs: $obs'}',
        ),
      ),
    );
    await _mostrarAcoesRelatorioFechamentoCaixa(
      operador: operadorFechamento,
      aberturaEm: aberturaFechamento,
      fechamentoEm: fechamentoEm,
      fundoTroco: fundoAbertura,
      suprimentos: suprimentos,
      sangrias: sangrias,
      esperadoDinheiro: esperados['dinheiro'] ?? 0,
      esperadoPix: esperados['pix'] ?? 0,
      esperadoDebito: esperados['debito'] ?? 0,
      esperadoCredito: esperados['credito'] ?? 0,
      declaradoDinheiro: declaradoDinheiro,
      declaradoPix: declaradoPix,
      declaradoDebito: declaradoDebito,
      declaradoCredito: declaradoCredito,
      observacao: obs,
    );
  }

  Future<Uint8List> _gerarRelatorioFechamentoPdfBytes({
    required String operador,
    required DateTime? aberturaEm,
    required DateTime fechamentoEm,
    required double fundoTroco,
    required double suprimentos,
    required double sangrias,
    required double esperadoDinheiro,
    required double esperadoPix,
    required double esperadoDebito,
    required double esperadoCredito,
    required double declaradoDinheiro,
    required double declaradoPix,
    required double declaradoDebito,
    required double declaradoCredito,
    required String observacao,
  }) async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    final logoBytes = config.logoPath.trim().isNotEmpty
        ? await File(
            config.logoPath,
          ).readAsBytes().catchError((_) => Uint8List(0))
        : Uint8List(0);
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final doc = pw.Document();
    double dif(double declarado, double esperado) => declarado - esperado;
    final diferencaTotal = dif(declaradoDinheiro, esperadoDinheiro) +
        dif(declaradoPix, esperadoPix) +
        dif(declaradoDebito, esperadoDebito) +
        dif(declaradoCredito, esperadoCredito);
    pw.Widget linha(String forma, double esperado, double declarado) {
      final delta = dif(declarado, esperado);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          children: [
            pw.Expanded(flex: 2, child: pw.Text(forma)),
            pw.Expanded(child: pw.Text('Esp: ${_formatarMoeda(esperado)}')),
            pw.Expanded(child: pw.Text('Dec: ${_formatarMoeda(declarado)}')),
            pw.Expanded(
              child: pw.Text(
                'Dif: ${_formatarMoeda(delta)}',
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  config.nomeLoja,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (logoBytes.isNotEmpty)
                pw.Center(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 48),
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'RELATORIO DE FECHAMENTO DE CAIXA (X/Z)',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Operador: ${operador.isEmpty ? '-' : operador}'),
              pw.Text(
                'Abertura: ${aberturaEm == null ? '-' : dtFmt.format(aberturaEm.toLocal())}',
              ),
              pw.Text('Fechamento: ${dtFmt.format(fechamentoEm.toLocal())}'),
              pw.SizedBox(height: 8),
              pw.Text('Fundo inicial: ${_formatarMoeda(fundoTroco)}'),
              pw.Text('Suprimentos: ${_formatarMoeda(suprimentos)}'),
              pw.Text('Sangrias: ${_formatarMoeda(sangrias)}'),
              pw.Divider(),
              pw.Text(
                'Conferencia por forma de pagamento',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              linha('Dinheiro', esperadoDinheiro, declaradoDinheiro),
              linha('PIX', esperadoPix, declaradoPix),
              linha('Cartao debito', esperadoDebito, declaradoDebito),
              linha('Cartao credito', esperadoCredito, declaradoCredito),
              pw.Divider(),
              pw.Text(
                'Diferenca total: ${_formatarMoeda(diferencaTotal)} '
                '${diferencaTotal.abs() < 0.01 ? '(sem divergencia)' : diferencaTotal > 0 ? '(sobra)' : '(falta)'}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (observacao.trim().isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  'Observacao: $observacao',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _mostrarAcoesRelatorioFechamentoCaixa({
    required String operador,
    required DateTime? aberturaEm,
    required DateTime fechamentoEm,
    required double fundoTroco,
    required double suprimentos,
    required double sangrias,
    required double esperadoDinheiro,
    required double esperadoPix,
    required double esperadoDebito,
    required double esperadoCredito,
    required double declaradoDinheiro,
    required double declaradoPix,
    required double declaradoDebito,
    required double declaradoCredito,
    required String observacao,
  }) async {
    if (!mounted) return;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    final acao = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Relatorio de fechamento'),
          content: const Text('Deseja imprimir o fechamento ou salvar em PDF?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'fechar'),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Salvar PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'direto'),
              icon: const Icon(Icons.print),
              label: const Text('Impressao direta'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'imprimir'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir'),
            ),
          ],
        );
      },
    );
    if (!mounted || acao == null || acao == 'fechar') return;
    try {
      final pdfBytes = await _gerarRelatorioFechamentoPdfBytes(
        operador: operador,
        aberturaEm: aberturaEm,
        fechamentoEm: fechamentoEm,
        fundoTroco: fundoTroco,
        suprimentos: suprimentos,
        sangrias: sangrias,
        esperadoDinheiro: esperadoDinheiro,
        esperadoPix: esperadoPix,
        esperadoDebito: esperadoDebito,
        esperadoCredito: esperadoCredito,
        declaradoDinheiro: declaradoDinheiro,
        declaradoPix: declaradoPix,
        declaradoDebito: declaradoDebito,
        declaradoCredito: declaradoCredito,
        observacao: observacao,
      );
      if (acao == 'imprimir') {
        await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
        return;
      }
      if (acao == 'direto') {
        final printer = await widget.printService
            .resolverImpressoraPorNome(config.impressoraPadrao);
        if (printer == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Impressora padrao nao configurada/encontrada.')),
          );
          return;
        }
        await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => pdfBytes,
          name: 'Fechamento Caixa ${DateFormat('yyyyMMdd_HHmm').format(fechamentoEm)}',
          format: PdfPageFormat.a4,
        );
        return;
      }
      final path = await _escolherSalvarPdf(
        bytes: pdfBytes,
        suggestedFileName:
            'fechamento_caixa_${DateFormat('yyyyMMdd_HHmm').format(fechamentoEm)}.pdf',
        initialDirectory: config.pastaPadraoPdf.trim().isEmpty
            ? null
            : config.pastaPadraoPdf.trim(),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Relatorio salvo em: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel gerar/imprimir relatorio: $e')),
      );
    }
  }

  double _descontoAplicado(Venda venda) => _descontoCaixaAplicado(venda);

  double _totalComDesconto(Venda venda) => venda.total;

  /// Linhas do misto com valores proporcionais ao [totalComDesconto] exibido no caixa.
  List<PagamentoOrcamentoLinha> _linhasPagamentoEscaladasCaixa(
    Venda v,
    double totalComDesconto,
  ) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return const [];
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return const [];
    final fator = totalComDesconto / soma;
    return linhas
        .map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: (l.valor * fator),
            parcelas: l.parcelas,
          ),
        )
        .toList();
  }

  void _disposeMistoEdicao() {
    for (final c in _mistoValorControllers) {
      c.dispose();
    }
    _mistoValorControllers.clear();
    for (final f in _mistoValorFocusNodes) {
      f.dispose();
    }
    _mistoValorFocusNodes.clear();
    _mistoLinhasModelo.clear();
    _mistoPreparadoParaId = null;
  }

  /// Prepara campos do misto para conferencia manual no caixa.
  /// Os valores iniciam zerados para o operador digitar o recebido.
  void _prepararEdicaoMisto(Venda v) {
    _disposeMistoEdicao();
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return;
    }
    final tv = _totalComDesconto(v);
    final scaled = _linhasPagamentoEscaladasCaixa(v, tv);
    _mistoLinhasModelo = List<PagamentoOrcamentoLinha>.from(scaled);
    for (final linha in scaled) {
      final textoValor = linha.meio == 'fiado'
          ? linha.valor.toStringAsFixed(2).replaceAll('.', ',')
          : '0,00';
      _mistoValorControllers.add(TextEditingController(text: textoValor));
      _mistoValorFocusNodes.add(FocusNode());
    }
    _mistoPreparadoParaId = v.id;
  }

  double _valorFiadoMistoOrcamentoCaixa() =>
      PagamentoOrcamentoCodec.somaPorMeio(_mistoLinhasModelo, 'fiado');

  double _somaMistoRecebidaNoCaixaAgora() {
    final linhas = _linhasMistoDoFormulario();
    return linhas
        .where((l) => l.meio != 'fiado')
        .fold<double>(0, (s, l) => s + l.valor);
  }

  List<PagamentoOrcamentoLinha> _linhasMistoDoFormulario() {
    if (_mistoLinhasModelo.length != _mistoValorControllers.length) {
      return const [];
    }
    final out = <PagamentoOrcamentoLinha>[];
    for (var i = 0; i < _mistoLinhasModelo.length; i++) {
      final m = _mistoLinhasModelo[i];
      final valor = _parseValor(_mistoValorControllers[i].text) ?? 0;
      out.add(
        PagamentoOrcamentoLinha(
          meio: m.meio,
          valor: valor,
          parcelas: m.parcelas,
        ),
      );
    }
    return out;
  }

  String? _validarConferenciaMistoIgualOrcamento(Venda venda, double totalComDesconto) {
    final informado = _linhasMistoDoFormulario();
    final esperado = _linhasPagamentoEscaladasCaixa(venda, totalComDesconto);
    if (informado.length != esperado.length) {
      return 'Pagamento misto invalido para conferencia no caixa.';
    }
    for (var i = 0; i < esperado.length; i++) {
      final linhaEsperada = esperado[i];
      final linhaInformada = informado[i];
      if (linhaEsperada.meio == 'fiado') {
        continue;
      }
      if ((linhaInformada.valor - linhaEsperada.valor).abs() > _tolMistoPagamento) {
        final sufixoParcelas = linhaEsperada.meio == 'cartao_credito'
            ? ' (${linhaEsperada.parcelas}x)'
            : '';
        return 'Valor divergente em ${_rotuloFormaPagamento(linhaEsperada.meio)}$sufixoParcelas. '
            'Esperado: ${_formatarMoeda(linhaEsperada.valor)}.';
      }
    }
    return null;
  }

  void _recarregarOrcamentoSelecionadoAposAjusteItens() {
    final id = _selecionado?.id;
    if (id == null) return;
    _carregarOrcamentos();
    final atualizado = widget.vendaRepository.obterPorId(id);
    if (atualizado == null || !mounted) return;
    final avisoPagamento = atualizado.formaPagamento == 'misto' ||
        (atualizado.formaPagamento == 'fiado' &&
            atualizado.planoFiadoJson.trim().isNotEmpty);
    setState(() {
      _selecionado = atualizado;
      _prepararEdicaoMisto(atualizado);
      _sincronizarRecebidoPdVComOrcamento();
    });
    if (avisoPagamento) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Total atualizado. Revise valores de pagamento na cobranca.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _alternarTipoEntregaItemConferencia(
    Venda venda,
    ItemVenda item,
  ) async {
    if (_etapaCaixa != CaixaEtapa.conferencia) return;
    final tipoNovo = EntregaVendaHelper.proximoTipoItem(item.tipoEntregaItem);
    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .atualizarTipoEntregaItemOrcamentoRemoto(
          venda.id,
          item.id,
          tipoNovo,
        );
      } else {
        widget.vendaRepository.atualizarTipoEntregaItemOrcamento(
          venda.id,
          item.id,
          tipoNovo,
        );
      }
      await _registrarAuditoriaCaixa(
        'ajuste_tipo_entrega_item_orcamento',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'itemId': item.id,
          'produto': item.nomeProduto,
          'tipoAnterior': item.tipoEntregaItem,
          'tipoNovo': tipoNovo,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        '${item.nomeProduto}: '
        '${EntregaVendaHelper.rotuloTipoItem(tipoNovo)}',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel alterar a entrega: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  Future<void> _alterarQuantidadeItemConferencia(
    Venda venda,
    ItemVenda item,
    int delta,
  ) async {
    if (_etapaCaixa != CaixaEtapa.conferencia) return;
    final passo = ProdutoEmbalagem.passoQuantidadeArmazenada(
      produto: _produtoDoItem(item),
      quantidadeArmazenada: item.quantidade,
    );
    final novaQtd = item.quantidade + delta * passo;
    if (novaQtd <= 0) {
      await _removerItemConferencia(venda, item);
      return;
    }
    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .atualizarQuantidadeItemOrcamentoRemoto(
          venda.id,
          item.id,
          (novaQtd as num).round(),
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      } else {
        widget.vendaRepository.atualizarQuantidadeItemOrcamento(
          venda.id,
          item.id,
          novaQtd,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      }
      await _registrarAuditoriaCaixa(
        'ajuste_quantidade_item_orcamento',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'itemId': item.id,
          'produto': item.nomeProduto,
          'quantidadeAnterior': item.quantidade,
          'quantidadeNova': novaQtd,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        'Quantidade atualizada: ${item.nomeProduto} '
        '(${ProdutoEmbalagem.textoQuantidadeArmazenada(produto: _produtoDoItem(item), quantidadeArmazenada: novaQtd)}).',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel alterar quantidade: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  Future<void> _removerItemConferencia(Venda venda, ItemVenda item) async {
    if (_etapaCaixa != CaixaEtapa.conferencia) return;
    if (_itensVenda(venda).length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O orcamento precisa manter ao menos um item.'),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover item do orcamento?'),
        content: Text(
          '${item.nomeProduto}\n\n'
          'Quantidade: ${ProdutoEmbalagem.textoQuantidadeArmazenada(produto: _produtoDoItem(item), quantidadeArmazenada: item.quantidade)}\n'
          'Valor da linha: ${_formatarMoeda(_subtotalLinhaItem(item))}\n\n'
          'O total sera recalculado automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final gerente = await solicitarCredenciaisGerenteCaixa(
      context,
      _usuarioRepository,
    );
    if (gerente == null || !mounted) return;

    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .removerItemOrcamentoRemoto(
          venda.id,
          item.id,
          gerenteLogin: gerente.login,
          gerenteSenha: gerente.senha,
        );
      } else {
        widget.vendaRepository.removerItemOrcamento(venda.id, item.id);
      }
      await _registrarAuditoriaCaixa(
        'remover_item_orcamento_caixa',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'itemId': item.id,
          'produto': item.nomeProduto,
          'quantidade': item.quantidade,
          'subtotal': item.subtotal,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      CaixaFeedback.sucesso(
        context,
        'Item removido. Total do orcamento atualizado.',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel remover item: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  String? get _segmentoClienteConferencia {
    final id = _selecionado?.cliente.targetId ?? 0;
    if (id <= 0) return null;
    return _clienteDaVenda(_selecionado!)?.segmento;
  }

  String _precoListaPadraoConferencia(Venda venda) {
    final itens = _itensVenda(venda);
    if (itens.isEmpty) return 'preco1';
    final t = itens.first.precoTipo.trim();
    if (t == PromocaoCadastro.precoTipoPromo) return 'preco1';
    return t.isEmpty ? 'preco1' : t;
  }

  String _tipoEntregaPadraoConferencia(Venda venda) {
    if (_tipoEntregaNovoItemConferencia != null) {
      return EntregaVendaHelper.normalizarTipoItem(
        _tipoEntregaNovoItemConferencia,
      );
    }
    final itens = _itensVenda(venda);
    if (itens.isEmpty) {
      return EntregaVendaHelper.tipoRetirada;
    }
    return EntregaVendaHelper.normalizarTipoItem(
      itens.first.tipoEntregaItem,
    );
  }

  String _rotuloPrecoConferencia(String precoTipo) => switch (precoTipo) {
        PromocaoCadastro.precoTipoPromo => 'Promocao',
        'preco2' => 'Preco 2',
        'preco3' => 'Preco 3',
        _ => 'Preco 1',
      };

  double _precoExibicaoConsultaConferencia(Produto produto, String precoTipo) {
    final svc = _promoPreco;
    if (svc == null) {
      return PromocaoPrecoService.precoLista(produto, precoTipo);
    }
    return svc
        .resolver(
          produto,
          dataReferencia: DateTime.now(),
          precoTipoLista: precoTipo,
          segmentoCliente: _segmentoClienteConferencia,
        )
        .precoFinal;
  }

  double _quantidadeProdutoNoOrcamentoSelecionado(int produtoId) {
    final v = _selecionado;
    if (v == null) return 0;
    var soma = 0.0;
    for (final item in _itensVenda(v)) {
      if (item.produto.targetId == produtoId) {
        soma += item.quantidadeVendaEfetiva;
      }
    }
    return soma;
  }

  void _registrarProdutoRecenteConferencia(int produtoId) {
    if (produtoId <= 0) return;
    _produtosRecentesConferencia.remove(produtoId);
    _produtosRecentesConferencia.insert(0, produtoId);
    if (_produtosRecentesConferencia.length > 30) {
      _produtosRecentesConferencia.removeRange(30, _produtosRecentesConferencia.length);
    }
  }

  Future<void> _abrirConsultaProdutoConferencia({String? termo}) async {
    final venda = _selecionado;
    if (venda == null || _etapaCaixa != CaixaEtapa.conferencia) return;

    final texto = (termo ?? _pesquisaProdutoConferenciaController.text).trim();
    final precoLista = _precoListaPadraoConferencia(venda);
    final clienteId = venda.cliente.targetId;
    final cid = clienteId > 0 ? clienteId : null;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;

    final result = await Navigator.of(context, rootNavigator: true)
        .push<PdvConsultaProdutoResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PdvConsultaProdutosPage(
          produtoRepository: widget.produtoRepository,
          vendaRepository: widget.vendaRepository,
          termoInicial: texto,
          precoListaAtivoInicial: precoLista,
          clienteId: cid,
          produtosRecentesIds: List<int>.from(_produtosRecentesConferencia),
          formatarMoeda: _formatarMoeda,
          rotuloPreco: _rotuloPrecoConferencia,
          precoUnitarioDe: _precoExibicaoConsultaConferencia,
          resolverPromocao: (p, t) {
            final svc = _promoPreco;
            if (svc == null) {
              return PromocaoPrecoResult.semPromocao(
                precoFinal: PromocaoPrecoService.precoLista(p, t),
                precoBasePreco1: PromocaoPrecoService.preco1Base(p),
                precoTipo: t,
              );
            }
            return svc.resolver(
              p,
              dataReferencia: DateTime.now(),
              precoTipoLista: t,
              segmentoCliente: _segmentoClienteConferencia,
            );
          },
          campanhasVigentesDe: (p) =>
              _promoPreco?.listarCampanhasVigentesParaProduto(
                p,
                dataReferencia: DateTime.now(),
                segmentoCliente: _segmentoClienteConferencia,
              ) ??
              const [],
          quantidadeNoOrcamentoDe: _quantidadeProdutoNoOrcamentoSelecionado,
          kitOrcamentoRepository: _kitOrcamentoRepo,
          sugestaoVendaRepository: _sugestaoVendaRepo,
          mostrarMargemGerente: UsuarioPermissaoHelper.tem(
            widget.usuarioLogado,
            PermissaoUsuario.verCustoMargem,
          ),
          margemMinimaPadrao: config.margemMinimaPercentualPadrao,
          rotulosDeposito: const PdvConsultaDepositoRotulos(),
        ),
      ),
    );

    if (!mounted) return;
    _pesquisaProdutoConferenciaController.clear();
    if (result == null) {
      _pesquisaProdutoConferenciaFocus.requestFocus();
      return;
    }

    await _aplicarProdutoConsultaConferencia(venda, result, precoLista);
  }

  Future<void> _aplicarProdutoConsultaConferencia(
    Venda venda,
    PdvConsultaProdutoResult result,
    String precoLista,
  ) async {
    _registrarProdutoRecenteConferencia(result.produto.id);

    if (result.inserirKit) {
      await _inserirKitConferencia(
        venda,
        result.kitInserirId!,
        result.quantidadeKitsInserir!,
        precoLista: result.precoListaAtivo.isNotEmpty
            ? result.precoListaAtivo
            : precoLista,
      );
      return;
    }

    final tipoPadrao = _tipoEntregaPadraoConferencia(venda);
    if (result.adicaoDireta) {
      await _adicionarProdutoAoOrcamentoConferencia(
        venda,
        result.produto,
        1,
        precoLista: result.precoListaAtivo.isNotEmpty
            ? result.precoListaAtivo
            : precoLista,
        tipoEntregaItem: tipoPadrao,
      );
      return;
    }
    if (result.quantidadeDireta != null && result.quantidadeDireta! > 0) {
      await _adicionarProdutoAoOrcamentoConferencia(
        venda,
        result.produto,
        result.quantidadeDireta!,
        precoLista: result.precoListaAtivo.isNotEmpty
            ? result.precoListaAtivo
            : precoLista,
        tipoEntregaItem: tipoPadrao,
      );
      return;
    }

    final escolha = await _perguntarQuantidadeProdutoConferencia(
      result.produto,
      quantidadeSugerida: 1,
      tipoEntregaInicial: tipoPadrao,
    );
    if (escolha == null || !mounted) return;
    setState(() => _tipoEntregaNovoItemConferencia = escolha.tipoEntregaItem);
    await _adicionarProdutoAoOrcamentoConferencia(
      venda,
      result.produto,
      escolha.quantidade,
      precoLista: result.precoListaAtivo.isNotEmpty
          ? result.precoListaAtivo
          : precoLista,
      tipoEntregaItem: escolha.tipoEntregaItem,
    );
  }

  Future<void> _inserirKitConferencia(
    Venda venda,
    int kitId,
    int quantidadeKits, {
    required String precoLista,
  }) async {
    final kitRepo = _kitOrcamentoRepo;
    if (kitRepo == null) return;
    final montada = PdvKitOrcamentoInsercaoUtil.montar(
      kitRepository: kitRepo,
      produtoRepository: widget.produtoRepository,
      kitId: kitId,
      quantidadeKits: quantidadeKits,
    );
    if (montada == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kit invalido ou sem itens ativos para inserir.'),
        ),
      );
      return;
    }

    final tipoPadrao = _tipoEntregaPadraoConferencia(venda);
    for (final linha in montada.linhas) {
      await _adicionarProdutoAoOrcamentoConferencia(
        venda,
        linha.produto,
        linha.quantidade.round(),
        precoLista: precoLista,
        tipoEntregaItem: tipoPadrao,
      );
    }

    if (!mounted) return;
    if (montada.itensIgnorados > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${montada.itensIgnorados} item(ns) do kit '
            '"${montada.nomeKit}" ignorados (produto inativo ou removido).',
          ),
        ),
      );
    }
  }

  double? _parseQuantidadeExibicaoConferencia(Produto produto, String texto) {
    return QuantidadeVendaUtil.parseEntradaPdv(
      texto,
      fracionada: true,
    );
  }

  Future<({double quantidade, String tipoEntregaItem})?>
      _perguntarQuantidadeProdutoConferencia(
    Produto produto, {
    required int quantidadeSugerida,
    required String tipoEntregaInicial,
  }) async {
    final ctrl = TextEditingController(text: '$quantidadeSugerida');
    var tipo = EntregaVendaHelper.normalizarTipoItem(tipoEntregaInicial);

    void confirmar(BuildContext ctx) {
      final q = _parseQuantidadeExibicaoConferencia(produto, ctrl.text);
      if (q == null || q <= 0) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              'Informe quantidade valida (ex.: 5,75).',
            ),
          ),
        );
        return;
      }
      Navigator.pop(
        ctx,
        (quantidade: q, tipoEntregaItem: tipo),
      );
    }

    final resultado =
        await showDialog<({double quantidade, String tipoEntregaItem})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Adicionar — ${produto.nome}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(tipo),
                initialValue: tipo,
                decoration: const InputDecoration(
                  labelText: 'Entrega deste item',
                ),
                items: [
                  for (final t in EntregaVendaHelper.tiposItem)
                    DropdownMenuItem(
                      value: t,
                      child: Text(EntregaVendaHelper.rotuloTipoItem(t)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => tipo = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [
                  QuantidadePdvInputFormatter(fracionada: true),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  hintText: 'Ex.: 5,75',
                  helperText: 'Aceita decimais (ex.: 5,75 ou 4,50).',
                ),
                onSubmitted: (_) => confirmar(ctx),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => confirmar(ctx),
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return resultado;
  }

  Future<void> _adicionarProdutoAoOrcamentoConferencia(
    Venda venda,
    Produto produto,
    num quantidade, {
    required String precoLista,
    required String tipoEntregaItem,
  }) async {
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    if (quantidade <= 0) return;
    final qExibicao = quantidade.toDouble();
    final qEstoquePromo = qExibicao.ceil();
    final fracionada = QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
      emUnidadeCompra: false,
      cadastroFracionado: produto.permiteQuantidadeFracionada,
      quantidadeVenda: qExibicao,
    );
    final qArmazenada = QuantidadeVendaUtil.paraArmazenamento(
      qExibicao,
      fracionada: fracionada,
    );
    if (qArmazenada <= 0) return;

    final svc = _promoPreco;
    final resPreco = svc == null
        ? PromocaoPrecoResult.semPromocao(
            precoFinal: PromocaoPrecoService.precoLista(produto, precoLista),
            precoBasePreco1: PromocaoPrecoService.preco1Base(produto),
            precoTipo: precoLista,
          )
        : svc.resolver(
            produto,
            dataReferencia: DateTime.now(),
            quantidade: qEstoquePromo,
            precoTipoLista: precoLista,
            segmentoCliente: _segmentoClienteConferencia,
          );

    if (resPreco.emPromocao) {
      if (resPreco.quantidadeMaximaPorVenda > 0 &&
          qEstoquePromo > resPreco.quantidadeMaximaPorVenda) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite da promocao: max. ${resPreco.quantidadeMaximaPorVenda} '
              'un. para ${produto.nome}.',
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
          if (!ok || !mounted) return;
        }
      }
    }

    if (!_permitirVendaSemEstoque) {
      final fresh = widget.produtoRepository.obterPorId(produto.id) ?? produto;
      final disp = fresh.estoqueLivreParaVenda;
      final ja = _quantidadeProdutoNoOrcamentoSelecionado(produto.id);
      if (ja + qExibicao > disp) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque insuficiente para ${produto.nome}. '
              'Disponivel: $disp (ja no orcamento: $ja).',
            ),
          ),
        );
        return;
      }
    }

    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .adicionarItemAoOrcamentoRemoto(
          venda.id,
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: qArmazenada,
            precoUnitario: resPreco.precoFinal,
            precoTipo: resPreco.precoTipo,
            tipoEntregaItem: tipoEntregaItem,
            promocaoId: resPreco.promocaoId,
            promocaoNomeSnapshot: resPreco.promocaoNome,
          ),
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      } else {
        widget.vendaRepository.adicionarItemAoOrcamento(
          venda.id,
          ItemVendaInput(
            produtoId: produto.id,
            quantidade: qArmazenada,
            precoUnitario: resPreco.precoFinal,
            precoTipo: resPreco.precoTipo,
            tipoEntregaItem: tipoEntregaItem,
            promocaoId: resPreco.promocaoId,
            promocaoNomeSnapshot: resPreco.promocaoNome,
          ),
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      }
      await _registrarAuditoriaCaixa(
        'adicionar_item_orcamento_caixa',
        detalhes: {
          'vendaId': venda.id,
          'numeroOrcamento': venda.numeroOrcamento,
          'produtoId': produto.id,
          'produto': produto.nome,
          'quantidade': qExibicao,
          'precoUnitario': resPreco.precoFinal,
          'tipoEntregaItem': tipoEntregaItem,
        },
      );
      if (!mounted) return;
      _recarregarOrcamentoSelecionadoAposAjusteItens();
      final qTxt = QuantidadeVendaUtil.formatarExibicao(
        qExibicao,
        fracionada: true,
      );
      CaixaFeedback.sucesso(
        context,
        '${produto.nome} adicionado ($qTxt un. · '
        '${EntregaVendaHelper.rotuloCurtoTipoItem(tipoEntregaItem)}).',
      );
      _pesquisaProdutoConferenciaFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel adicionar produto: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  Future<void> _alterarFormaPagamentoCaixa(Venda venda) async {
    final gerente = await solicitarCredenciaisGerenteCaixa(
      context,
      _usuarioRepository,
    );
    if (gerente == null || !mounted) return;

    final totalExibido = _totalComDesconto(venda);
    final resultado = await showDialog<DadosPagamentoOrcamento>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlterarPagamentoCaixaDialog(
        venda: venda,
        totalExibidoCaixa: totalExibido,
        totalGravacaoOrcamento: venda.total,
        clienteVinculado: venda.cliente.targetId > 0,
        formatarMoeda: _formatarMoeda,
      ),
    );
    if (resultado == null || !mounted) return;

    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .alterarPagamentoOrcamentoRemoto(
          venda.id,
          resultado,
          gerenteLogin: gerente.login,
          gerenteSenha: gerente.senha,
        );
      } else {
        widget.vendaRepository.alterarPagamentoOrcamento(venda.id, resultado);
      }
      _carregarOrcamentos();
      if (!mounted) return;
      final atualizado = widget.vendaRepository.obterPorId(venda.id);
      if (atualizado != null) {
        setState(() {
          _selecionado = atualizado;
          _prepararEdicaoMisto(atualizado);
          _sincronizarRecebidoPdVComOrcamento();
        });
      }
      CaixaFeedback.sucesso(
        context,
        'Forma de pagamento atualizada. Confira os valores e finalize.',
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel alterar pagamento: ${LanApiFeedback.mensagem(e)}',
      );
    }
  }

  static const double _tolMistoPagamento = 0.05;

  /// Reduz linhas do formulario do caixa para somar [targetTotal] (valor da venda).
  /// Quando o cliente paga a mais (ex.: entrega nota maior em dinheiro), o excesso
  /// vira troco e nao entra na soma gravada no orcamento.
  List<PagamentoOrcamentoLinha> _normalizarLinhasMistoGravacao(
    List<PagamentoOrcamentoLinha> form,
    double targetTotal,
  ) {
    if (form.isEmpty) return form;
    final soma = PagamentoOrcamentoCodec.soma(form);
    if (soma <= targetTotal + _tolMistoPagamento) {
      return List<PagamentoOrcamentoLinha>.from(form);
    }
    final nd = <PagamentoOrcamentoLinha>[];
    for (final l in form) {
      if (l.meio != 'dinheiro') {
        nd.add(l);
      }
    }
    final sNd = PagamentoOrcamentoCodec.soma(nd);
    if (sNd < targetTotal - 1e-6) {
      final dVenda = targetTotal - sNd;
      return [
        ...nd.map(
          (l) => PagamentoOrcamentoLinha(
            meio: l.meio,
            valor: l.valor,
            parcelas: l.parcelas,
          ),
        ),
        PagamentoOrcamentoLinha(meio: 'dinheiro', valor: dVenda, parcelas: 1),
      ];
    }
    return _escalarLinhasParaTotalMisto(nd, targetTotal);
  }

  List<PagamentoOrcamentoLinha> _escalarLinhasParaTotalMisto(
    List<PagamentoOrcamentoLinha> linhas,
    double targetTotal,
  ) {
    if (linhas.isEmpty) return linhas;
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return linhas;
    final fator = targetTotal / soma;
    final out = <PagamentoOrcamentoLinha>[];
    for (final l in linhas) {
      out.add(
        PagamentoOrcamentoLinha(
          meio: l.meio,
          valor: l.valor * fator,
          parcelas: l.parcelas,
        ),
      );
    }
    var soma2 = PagamentoOrcamentoCodec.soma(out);
    final diff = targetTotal - soma2;
    if (out.isNotEmpty && diff.abs() > 1e-4) {
      final i = out.length - 1;
      final u = out[i];
      out[i] = PagamentoOrcamentoLinha(
        meio: u.meio,
        valor: (u.valor + diff).clamp(0, double.infinity),
        parcelas: u.parcelas,
      );
    }
    return out;
  }

  /// Parte em dinheiro apos desconto do caixa (escala proporcional ao total).
  double _parteDinheiroNaFinalizacao(Venda v, double totalComDesconto) {
    if (v.formaPagamento != 'misto') {
      return v.formaPagamento == 'dinheiro' ? totalComDesconto : 0;
    }
    final linhasForm = _linhasMistoDoFormulario();
    if (linhasForm.isNotEmpty) {
      return PagamentoOrcamentoCodec.somaPorMeio(linhasForm, 'dinheiro');
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    final soma = PagamentoOrcamentoCodec.soma(linhas);
    if (soma <= 0.001) return 0;
    final parte = PagamentoOrcamentoCodec.somaPorMeio(linhas, 'dinheiro');
    return parte * (totalComDesconto / soma);
  }

  /// Campo separado de especie/troco: apenas venda 100% em dinheiro.
  /// No pagamento misto, valores e conferencia ficam no painel misto.
  bool _caixaPrecisaValorRecebidoDinheiro(Venda v) {
    return v.formaPagamento == 'dinheiro';
  }

  /// Pagamento misto: mantem valores do PDV no painel misto.
  /// Dinheiro puro: campo "Valor recebido" vazio para o operador digitar.
  void _sincronizarRecebidoPdVComOrcamento() {
    final v = _selecionado;
    if (v == null) return;
    if (v.formaPagamento == 'misto') {
      final linhas = _linhasMistoDoFormulario();
      final d = PagamentoOrcamentoCodec.somaPorMeio(linhas, 'dinheiro');
      if (d > 0.001) {
        final texto = d.toStringAsFixed(2).replaceAll('.', ',');
        _valorRecebidoController.value = TextEditingValue(
          text: texto,
          selection: TextSelection.collapsed(offset: texto.length),
        );
        _valorRecebido = d;
      } else {
        _valorRecebidoController.clear();
        _valorRecebido = null;
      }
      return;
    }
    if (v.formaPagamento == 'dinheiro') {
      _valorRecebidoController.clear();
      _valorRecebido = null;
      return;
    }
    _valorRecebidoController.clear();
    _valorRecebido = null;
  }

  String _textoDetalheLinhasPagamento(List<PagamentoOrcamentoLinha> linhas) {
    if (linhas.isEmpty) return '';
    return linhas
        .map(
          (l) =>
              '${_rotuloFormaPagamento(l.meio)} ${_formatarMoeda(l.valor)}'
              '${l.meio == 'cartao_credito' ? ' ${l.parcelas}x' : ''}',
        )
        .join(' + ');
  }

  String _rotuloPagamentoCabecalho(Venda v) {
    if (v.formaPagamento != 'misto' || v.pagamentosJson.trim().isEmpty) {
      return '${_rotuloFormaPagamento(v.formaPagamento)}'
          '${v.formaPagamento == 'cartao_credito' ? ' | ${v.quantidadeParcelas}x' : ''}';
    }
    final linhas = PagamentoOrcamentoCodec.decode(v.pagamentosJson);
    if (linhas.isEmpty) return 'Misto';
    return _textoDetalheLinhasPagamento(linhas);
  }

  /// Na finalizacao, valores do misto no caixa podem divergir do JSON do orcamento ate gravar.
  String _rotuloPagamentoResumoNaFinalizacao(Venda venda) {
    if (venda.formaPagamento == 'misto') {
      final textoForm = _textoDetalheLinhasPagamento(_linhasMistoDoFormulario());
      if (textoForm.isNotEmpty) return textoForm;
    }
    return _rotuloPagamentoCabecalho(venda);
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
      case 'vale':
        return 'Vale de credito';
      case 'transferencia':
        return 'Transferencia';
      case 'misto':
        return 'Misto';
      case 'dinheiro':
      default:
        return 'Dinheiro';
    }
  }

  String _textoEntregaCaixa(Venda v) =>
      EntregaVendaHelper.textoEntregaCabecalhoVenda(
        v,
        itens: _itensVenda(v),
      );

  bool _vendaExigeDadosCarreto(Venda v) =>
      EntregaVendaHelper.vendaTemItensCarreto(
        v,
        itens: _itensVenda(v),
      );

  Cliente? _clienteDaVenda(Venda venda) {
    return VendaRelacaoSafe.cliente(
      venda,
      clienteRepository: widget.clienteRepository,
    );
  }

  Vendedor? _vendedorDaVenda(Venda venda) {
    return VendaRelacaoSafe.vendedor(
      venda,
      vendedorRepository: widget.vendedorRepository,
    );
  }

  String _rotuloVendedorUmLinha(Venda venda) {
    final v = _vendedorDaVenda(venda);
    if (v == null) {
      return 'Sem vendedor';
    }
    final nome = v.apelido.trim().isNotEmpty
        ? v.apelido.trim()
        : v.nomeCompleto.trim();
    final codigo = v.codigoInterno.trim();
    return codigo.isEmpty ? nome : '$codigo · $nome';
  }

  DateTime? _ultimaVendaFinalizada() {
    return widget.vendaRepository.dataUltimaVendaFinalizada();
  }

  bool _horarioSistemaInconsistente() {
    final agora = DateTime.now();
    final ultima = _ultimaVendaFinalizada();
    if (ultima == null) return false;
    return agora.isBefore(ultima.subtract(const Duration(minutes: 2)));
  }

  Future<void> _abrirAjusteDataHoraSO() async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'ms-settings:dateandtime']);
      } else if (Platform.isLinux) {
        await Process.start('sh', ['-c', 'gnome-control-center datetime']);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          'x-apple.systempreferences:com.apple.preference.datetime',
        ]);
      }
    } catch (_) {}
  }

  double _valorFiadoEfetivoNaFinalizacao(Venda venda, double totalVenda) {
    if (venda.formaPagamento == 'misto') {
      final doForm = PagamentoOrcamentoCodec.somaPorMeio(
        _linhasMistoDoFormulario(),
        'fiado',
      );
      if (doForm > 0.001) return doForm;
      return PagamentoOrcamentoCodec.somaPorMeio(
        PagamentoOrcamentoCodec.decode(venda.pagamentosJson),
        'fiado',
      );
    }
    if (venda.formaPagamento == 'fiado') {
      return totalVenda;
    }
    return 0;
  }

  ValeCreditoService get _valesServico =>
      ValeCreditoService.deVendaRepository(widget.vendaRepository);

  /// Entre o PDV escolher o vale e o caixa fechar, outro terminal pode ter
  /// gasto o mesmo codigo. Confere antes de finalizar, quando ainda da para
  /// voltar atras.
  Future<String?> _conferirValesAntesDeFinalizar(
    List<PagamentoOrcamentoLinha> linhas,
  ) async {
    final doVale = PagamentoOrcamentoCodec.linhasVale(linhas);
    if (doVale.isEmpty) return null;
    final servico = _valesServico;
    if (!servico.disponivel) {
      return 'Sem conexao com o servidor para conferir o vale.';
    }
    for (final l in doVale) {
      try {
        final vale = await servico.buscarPorCodigo(l.codigoVale);
        if (vale == null) {
          return 'Vale ${ValeCreditoCodigo.formatar(l.codigoVale)} nao '
              'encontrado.';
        }
        final avaliacao = vale.avaliar(l.valor);
        if (!avaliacao.podeUsar) {
          return 'Vale ${vale.codigoFormatado}: ${avaliacao.motivo}';
        }
        if (avaliacao.valorAplicavel + 0.004 < l.valor) {
          return 'Vale ${vale.codigoFormatado} tem so '
              '${_formatarMoeda(vale.saldo)} de saldo agora. '
              'Refaca o pagamento no PDV.';
        }
      } catch (e) {
        return 'Nao foi possivel conferir o vale: $e';
      }
    }
    return null;
  }

  /// Baixa o vale depois que a venda existe, para o uso ficar amarrado a ela.
  Future<void> _baixarValesDaVenda(Venda vendaFinalizada) async {
    final linhas = PagamentoOrcamentoCodec.linhasVale(
      PagamentoOrcamentoCodec.decode(vendaFinalizada.pagamentosJson),
    );
    if (linhas.isEmpty) return;
    final servico = _valesServico;
    final falhas = <String>[];
    for (final l in linhas) {
      try {
        await servico.resgatar(
          valeId: l.valeId,
          valor: l.valor,
          registradoPor: widget.usuarioLogado.login,
          vendaId: vendaFinalizada.id,
          numeroVenda: vendaFinalizada.numeroOrcamento,
        );
      } catch (e) {
        falhas.add(
          '${ValeCreditoCodigo.formatar(l.codigoVale)} '
          '(${_formatarMoeda(l.valor)}): $e',
        );
      }
    }
    if (falhas.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vale nao foi baixado'),
        content: Text(
          'A venda foi finalizada, mas o vale abaixo nao pode ser baixado. '
          'Cobre o valor por outro meio ou chame o responsavel:\n\n'
          '${falhas.join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizarOrcamento(Venda venda) async {
    if (_finalizandoVenda) return;
    if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
    if (!_caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abra o caixa antes de finalizar vendas.'),
        ),
      );
      return;
    }
    if (_horarioSistemaInconsistente()) {
      if (!mounted) return;
      final ultima = _ultimaVendaFinalizada();
      final ultimaFmt = ultima == null
          ? '-'
          : DateFormat('dd/MM/yyyy HH:mm:ss').format(ultima.toLocal());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Relogio do sistema inconsistente. Ultima venda: $ultimaFmt. '
            'Corrija data/hora no Windows para finalizar no caixa.',
          ),
          action: SnackBarAction(
            label: 'Ajustar',
            onPressed: () {
              _abrirAjusteDataHoraSO();
            },
          ),
        ),
      );
      return;
    }

    final descontoAplicado = _descontoAplicado(venda);
    final totalVenda = _totalComDesconto(venda);
    final valorFiado = _valorFiadoEfetivoNaFinalizacao(venda, totalVenda);
    final clienteId = venda.cliente.targetId;
    if (valorFiado > 0.001 && clienteId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Orcamento com fiado exige cliente vinculado. Edite o orcamento no PDV.',
          ),
        ),
      );
      return;
    }
    if (valorFiado > 0.001) {
      final plano = PlanoFiadoCodec.decode(venda.planoFiadoJson);
      if (!PlanoFiadoCodec.validarContraValor(plano, valorFiado)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Orçamento fiado sem plano de parcelas válido. '
              'Edite no PDV e defina vencimentos antes de finalizar.',
            ),
          ),
        );
        return;
      }
    }
    if (valorFiado > 0.001 && clienteId > 0) {
      late final dynamic r;
      try {
        if (widget.vendaRepository is VendaApiRepository) {
          r = await (widget.vendaRepository as VendaApiRepository)
              .validarLimiteCreditoRemoto(
            clienteId: clienteId,
            valorFiadoOperacao: valorFiado,
          );
        } else {
          r = widget.vendaRepository.validarLimiteCredito(
            clienteId: clienteId,
            valorFiadoOperacao: valorFiado,
          );
        }
      } catch (e) {
        if (!mounted) return;
        CaixaFeedback.erro(
          context,
          'Falha ao validar limite de credito: ${LanApiFeedback.mensagem(e)}',
        );
        return;
      }
      if (!r.permitido) {
        if (!mounted) return;
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
        return;
      }
    }
    late final double totalRecebido;
    late final double trocoFinal;
    if (venda.formaPagamento == 'misto') {
      final linhasBruto = _linhasMistoDoFormulario();
      final fiado = PagamentoOrcamentoCodec.somaPorMeio(linhasBruto, 'fiado');
      final recebidoCaixa = linhasBruto
          .where((l) => l.meio != 'fiado')
          .fold<double>(0, (s, l) => s + l.valor);
      final aPagarAgora = (totalVenda - fiado).clamp(0, double.infinity).toDouble();
      totalRecebido = recebidoCaixa + fiado;
      trocoFinal =
          (recebidoCaixa - aPagarAgora).clamp(0, double.infinity).toDouble();
    } else {
      final parteDinheiro = _parteDinheiroNaFinalizacao(venda, totalVenda);
      totalRecebido = parteDinheiro > 0.001
          ? (_valorRecebido ?? 0)
          : totalVenda;
      trocoFinal = parteDinheiro > 0.001
          ? ((_valorRecebido ?? 0) - parteDinheiro)
              .clamp(0, double.infinity)
              .toDouble()
          : 0.0;
    }
    final itensCount = _itensVenda(venda).length;

    if (venda.formaPagamento == 'misto') {
      final linhasBruto = _linhasMistoDoFormulario();
      final fiado = PagamentoOrcamentoCodec.somaPorMeio(linhasBruto, 'fiado');
      final recebidoCaixa = linhasBruto
          .where((l) => l.meio != 'fiado')
          .fold<double>(0, (s, l) => s + l.valor);
      final aPagarAgora = (totalVenda - fiado).clamp(0, double.infinity).toDouble();
      final divergenciaMisto = _validarConferenciaMistoIgualOrcamento(
        venda,
        totalVenda,
      );
      if (divergenciaMisto != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(divergenciaMisto)),
        );
        return;
      }
      if (recebidoCaixa < aPagarAgora - _tolMistoPagamento) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pagamento misto: recebido agora (${_formatarMoeda(recebidoCaixa)}) '
              'menor que o esperado (${_formatarMoeda(aPagarAgora)}). '
              '${fiado > 0.001 ? 'Fiado ${_formatarMoeda(fiado)} ja esta no orcamento.' : ''}',
            ),
          ),
        );
        return;
      }
      final linhas = _normalizarLinhasMistoGravacao(linhasBruto, totalVenda);
      for (final l in linhas) {
        if (l.meio == 'cartao_debito' && l.parcelas != 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cartao de debito deve ser a vista em cada linha.'),
            ),
          );
          return;
        }
      }
    } else {
      if (venda.formaPagamento == 'dinheiro') {
        final recebido = _valorRecebido ?? 0;
        if (recebido < totalVenda) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Valor recebido insuficiente para finalizar em dinheiro.',
              ),
            ),
          );
          return;
        }
      }
      if (venda.formaPagamento == 'cartao_debito' &&
          venda.quantidadeParcelas != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cartao de debito deve ser sempre a vista (1x).'),
          ),
        );
        return;
      }
    }
    final planoFiado = valorFiado > 0.001
        ? PlanoFiadoCodec.decode(venda.planoFiadoJson)
        : const <PlanoFiadoParcela>[];
    var confirmarFinalizacao = true;
    if (_deveExibirDialogResumoFinalizacao(venda, valorFiado)) {
      confirmarFinalizacao =
          await _mostrarResumoFechamentoVenda(
                numeroOrcamento: venda.numeroOrcamento,
                textoPagamento: _rotuloPagamentoResumoNaFinalizacao(venda),
                textoPlanoFiado: planoFiado.isEmpty
                    ? null
                    : PlanoFiadoCodec.formatarResumoLinhas(planoFiado),
                totalVenda: totalVenda,
                descontoAplicado: descontoAplicado,
                totalRecebido: totalRecebido,
                troco: trocoFinal,
                quantidadeItens: itensCount,
              ) ??
              false;
    }
    if (confirmarFinalizacao != true) {
      return;
    }
    if (!mounted) return;

    final erroVale = await _conferirValesAntesDeFinalizar(
      PagamentoOrcamentoCodec.decode(venda.pagamentosJson),
    );
    if (erroVale != null) {
      if (!mounted) return;
      CaixaFeedback.erro(context, erroVale);
      return;
    }
    if (!mounted) return;

    setState(() => _finalizandoVenda = true);
    try {
      if (venda.formaPagamento == 'misto') {
        final linhasBruto = _linhasMistoDoFormulario();
        if (linhasBruto.isNotEmpty) {
          final linhasConf =
              _normalizarLinhasMistoGravacao(linhasBruto, totalVenda);
          if (widget.vendaRepository is VendaApiRepository) {
            await (widget.vendaRepository as VendaApiRepository)
                .substituirPagamentosMistoOrcamentoRemoto(
              venda.id,
              linhasConf,
            );
          } else {
            widget.vendaRepository.substituirPagamentosMistoOrcamento(
              venda.id,
              linhasConf,
            );
          }
        }
      }
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .converterOrcamentoParaVendaRemoto(
          venda.id,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
          valorRecebidoCaixa: totalRecebido,
          valorTrocoCaixa: trocoFinal,
        );
      } else {
        widget.vendaRepository.converterOrcamentoParaVenda(
          venda.id,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
        widget.vendaRepository.registrarRecebidoTrocoCaixa(
          vendaId: venda.id,
          valorRecebido: totalRecebido,
          valorTroco: trocoFinal,
        );
        await LanSyncScheduler.solicitarSyncPrioritario();
      }
      // Antes de qualquer retorno por unmount: a venda ja existe e o vale
      // precisa ser baixado, senao o cliente leva a mercadoria e continua
      // com o credito inteiro.
      await _baixarValesDaVenda(
        widget.vendaRepository.obterPorId(venda.id) ?? venda,
      );
      // KPI "Vendas hoje" no Inicio (PC servidor e terminais via WS).
      SyncRefreshHub.instance.notificarDadosAtualizados();
      if (!mounted) return;
      final vendaFinalizada = widget.vendaRepository.obterPorId(venda.id) ?? venda;
      // Forca UI do PC1/terminal a reler estoque apos reserva na finalizacao.
      try {
        widget.produtoRepository.atualizarCacheAposMovimentoEstoque();
      } catch (_) {}
      _carregarOrcamentos();
      _atualizarListaUltimasVendasFinalizadasCaixa();
      if (!mounted) return;
      final numCupom =
          vendaFinalizada.numeroOrcamento > 0
              ? vendaFinalizada.numeroOrcamento
              : venda.numeroOrcamento;
      await _registrarUltimoTrocoFinalizado(
        vendaId: vendaFinalizada.id,
        numeroOrcamento: numCupom,
        troco: trocoFinal,
      );
      if (!mounted) return;
      CaixaFeedback.sucesso(context, 'Venda $numCupom finalizada.');
      unawaited(_tentarAbrirGavetaPosPagamento());
      final sessaoPosVenda = CaixaPosVendaSessao(
        venda: vendaFinalizada,
        totalRecebido: totalRecebido,
        troco: trocoFinal,
      );
      if (_caixaFiscalNaoBloqueante) {
        _prepararCaixaPosProximaVenda();
        _agendarFiscalPosVendaEmSegundoPlano(sessaoPosVenda);
        _atualizarResumoNfcePendenteEmissao();
        return;
      }
      setState(() {
        _posVenda = sessaoPosVenda;
        _painelCobrancaAberto = false;
        _etapaCaixa = CaixaEtapa.fiscal;
        _selecionado = null;
        _valorRecebidoController.clear();
        _valorRecebido = null;
        _disposeMistoEdicao();
      });
      _agendarDocumentoFiscalAutomatico();
      _atualizarResumoNfcePendenteEmissao();
    } catch (e) {
      if (!mounted) return;
      if (_ehTimeoutFinalizacao(e)) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Aguardando servidor'),
            content: const Text(
              'Aguardando resposta do servidor. Nao feche a tela.\n\n'
              'Se a venda ja aparecer na listagem, nao finalize de novo.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      } else {
        CaixaFeedback.erro(
          context,
          'Nao foi possivel finalizar: ${LanApiFeedback.mensagem(e)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _finalizandoVenda = false);
      } else {
        _finalizandoVenda = false;
      }
    }
  }

  bool _ehTimeoutFinalizacao(Object e) {
    if (e is TimeoutException) return true;
    final m = LanApiFeedback.mensagem(e).toLowerCase();
    return m.contains('tempo esgotado') ||
        m.contains('timeout') ||
        m.contains('timed out');
  }

  /// NFC-e / NF-e 55 conforme pagamento. Comprovante (cupom) e oferecido
  /// sempre, em fluxo separado — independente desta acao.
  String? _acaoFiscalAutomaticaPorPagamento(Venda venda) {
    return CaixaFiscalAcaoHelper.acaoAutomaticaPorPagamento(
      venda: venda,
      cliente: _clienteDaVenda(venda),
    );
  }

  bool _bloqueiaNovaNfceNoCaixa(Venda venda) {
    return CaixaFiscalAcaoHelper.bloqueiaNovaNfceNoCaixa(
      venda: venda,
      cliente: _clienteDaVenda(venda),
    );
  }

  void _agendarDocumentoFiscalAutomatico() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_dispararDocumentoFiscalAutomatico());
    });
  }

  void _agendarFiscalPosVendaEmSegundoPlano(CaixaPosVendaSessao sessao) {
    unawaited(_executarFiscalPosVendaEmSegundoPlano(sessao));
  }

  /// Pergunta de comprovante para qualquer forma de pagamento.
  Future<void> _oferecerComprovantePosVenda(CaixaPosVendaSessao sessao) async {
    final venda =
        widget.vendaRepository.obterPorId(sessao.venda.id) ?? sessao.venda;
    await _imprimirCupomNaoFiscalPosVenda(
      venda: venda,
      totalRecebido: sessao.totalRecebido,
      troco: sessao.troco,
    );
  }

  Future<void> _executarFiscalPosVendaEmSegundoPlano(
    CaixaPosVendaSessao sessao,
  ) async {
    final venda =
        widget.vendaRepository.obterPorId(sessao.venda.id) ?? sessao.venda;

    // Sempre pergunta o comprovante (dinheiro, PIX, cartao, fiado, misto...).
    try {
      if (mounted) {
        await _oferecerComprovantePosVenda(sessao);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comprovante: ${LanApiFeedback.mensagem(e)}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    final vendaAtual =
        widget.vendaRepository.obterPorId(sessao.venda.id) ?? venda;
    final acao = _acaoFiscalAutomaticaPorPagamento(vendaAtual);
    if (acao == null || acao == 'cupom') {
      _atualizarResumoNfcePendenteEmissao();
      return;
    }
    if (_documentoFiscalCaixaJaAtendido(vendaAtual, acao)) {
      _atualizarResumoNfcePendenteEmissao();
      return;
    }

    if (acao == 'nfe55') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Venda ${vendaAtual.numeroOrcamento} exige NF-e 55. '
            'Abra Notas fiscais quando puder.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }

    try {
      if (acao == 'nfce') {
        final bloqueioCnpj = CaixaFiscalAcaoHelper.mensagemBloqueioNfceClienteCnpj(
          cliente: _clienteDaVenda(vendaAtual),
          venda: vendaAtual,
        );
        if (bloqueioCnpj != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(bloqueioCnpj)),
            );
          }
          return;
        }
        await _emitirNfceParaVenda(vendaAtual);
      }
      _atualizarResumoNfcePendenteEmissao();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Documento fiscal em segundo plano: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _dispararDocumentoFiscalAutomatico() async {
    if (!mounted ||
        _posVendaProcessando ||
        _documentoFiscalAutomaticoDisparado) {
      return;
    }
    if (_etapaCaixa != CaixaEtapa.fiscal || _posVenda == null) return;

    final sessao = _posVenda!;
    _documentoFiscalAutomaticoDisparado = true;

    // Sempre oferece o comprovante, independente do pagamento.
    setState(() => _posVendaProcessando = true);
    try {
      await _oferecerComprovantePosVenda(sessao);
      _atualizarPosVendaDoRepositorio();
    } finally {
      if (mounted) setState(() => _posVendaProcessando = false);
    }
    if (!mounted || _posVenda == null) return;

    final venda = _vendaPosCaixaAtualizada() ?? sessao.venda;
    final acao = _acaoFiscalAutomaticaPorPagamento(venda);
    if (acao == null || acao == 'cupom') {
      if (_vendaComDocumentoPosCaixaObrigatorio(venda)) {
        await _encerrarPosVendaFiscal();
      }
      return;
    }

    if (_documentoFiscalCaixaJaAtendido(venda, acao)) {
      await _encerrarPosVendaFiscal();
      return;
    }

    await _executarAcaoPosVendaFiscal(acao);
  }

  GavetaEscPosService get _gaveta =>
      _gavetaService ??= GavetaEscPosService(widget.appConfigRepository);

  Future<void> _tentarAbrirGavetaPosPagamento() async {
    final r = await _gaveta.abrirAposPagamento();
    if (!mounted || r.sucesso) return;
    if (r.codigo == GavetaResultadoCodigo.desativada) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.mensagem),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _testarGavetaManual() async {
    final r = await _gaveta.testarAbrir();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.mensagem)),
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
    if (selectedPath == null) {
      return null;
    }
    final normalizedPath = selectedPath.toLowerCase().endsWith('.pdf')
        ? selectedPath
        : '$selectedPath.pdf';
    final file = File(normalizedPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _atualizarPosVendaDoRepositorio() {
    final sessao = _posVenda;
    if (sessao == null) return;
    final v = widget.vendaRepository.obterPorId(sessao.venda.id);
    if (v != null && mounted) {
      setState(() => _posVenda = sessao.copyWith(venda: v));
    }
  }

  Future<void> _cancelarVendaNoCaixa(Venda venda) async {
    final resultado = await CancelarVendaUi.executar(
      context: context,
      vendaRepository: widget.vendaRepository,
      clienteRepository: widget.clienteRepository,
      usuarioRepository: _usuarioRepository,
      usuarioAtual: widget.usuarioAtual,
      podeCancelarVendas: widget.podeCancelarVendas,
      venda: venda,
    );
    if (!mounted) return;
    if (resultado != CancelarVendaUiResultado.sucesso) return;
    _carregarOrcamentos();
    await _aposMutacaoFiscalOuCancelamentoCaixa(vendaId: venda.id);
    if (!mounted) return;
    if (_posVenda?.venda.id == venda.id) {
      _prepararCaixaPosProximaVenda();
    }
  }

  Venda? _vendaPosCaixaAtualizada() {
    final sessao = _posVenda;
    if (sessao == null) return null;
    return widget.vendaRepository.obterPorId(sessao.venda.id) ?? sessao.venda;
  }

  bool _vendaComDocumentoPosCaixaObrigatorio(Venda venda) {
    return VendaDocumentoPosCaixa.podeEncerrarEtapaFiscal(venda);
  }

  bool _documentoFiscalCaixaJaAtendido(Venda venda, String acao) {
    return CaixaFiscalAcaoHelper.documentoFiscalJaAtendido(
      venda: venda,
      acao: acao,
    );
  }

  Future<void> _mostrarErroBaixaEstoqueAnomala(Venda venda) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
        title: const Text('Baixa de estoque pendente'),
        content: Text(
          'A venda foi finalizada, mas a baixa de estoque de '
          '${VendaDocumentoRotuloHelper.rotuloControleInterno(venda)} nao concluiu.\n\n'
          'Isso nao deveria ocorrer apos a finalizacao normal. Tente reprocessar. '
          'Se persistir, verifique produtos desvinculados nos itens.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
    if (!mounted || r != true) return;
    final ok = await _reprocessarBaixaEstoquePosFiscal(venda.id);
    if (!mounted || !ok) return;
    final atualizado = widget.vendaRepository.obterPorId(venda.id) ?? venda;
    if (_vendaComDocumentoPosCaixaObrigatorio(atualizado)) {
      await _encerrarPosVendaFiscal();
    }
  }

  Future<void> _encerrarPosVendaFiscal() async {
    final sessao = _posVenda;
    if (sessao == null) {
      _prepararCaixaPosProximaVenda();
      return;
    }
    final venda = _vendaPosCaixaAtualizada() ?? sessao.venda;
    if (!VendaDocumentoPosCaixa.estoqueOperacionalOk(venda)) {
      await _mostrarErroBaixaEstoqueAnomala(venda);
      return;
    }
    await _alertarVendaSemNfe55SeNecessario(venda);
    if (!mounted) return;
    _prepararCaixaPosProximaVenda();
  }

  Future<void> _executarAcaoPosVendaFiscal(String acao) async {
    final sessao = _posVenda;
    if (sessao == null || _posVendaProcessando) return;
    final venda = sessao.venda;

    if (acao == 'nfe55') {
      setState(() => _posVendaProcessando = true);
      try {
        final vendaId = venda.id;
        final usuarioNfe = await _resolverUsuarioSessaoParaNfe();
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => NfeGerenciamentoPage(
              vendaRepository: widget.vendaRepository,
              clienteRepository: widget.clienteRepository,
              appConfigRepository: widget.appConfigRepository,
              usuarioLogado: usuarioNfe,
              vendaIdInicial: vendaId,
            ),
          ),
        );
        if (!mounted) return;
        await _tentarBaixaEstoquePosNfe55Autorizada(vendaId);
        _atualizarPosVendaDoRepositorio();
        if (!mounted) return;
        final vendaAtual = _vendaPosCaixaAtualizada() ?? venda;
        if (vendaAtual.nfe55Autorizada &&
            _vendaComDocumentoPosCaixaObrigatorio(vendaAtual)) {
          await _encerrarPosVendaFiscal();
        }
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
      return;
    }

    if (acao == 'nfce') {
      final vendaAtual = _vendaPosCaixaAtualizada() ?? venda;
      final bloqueioCnpj = CaixaFiscalAcaoHelper.mensagemBloqueioNfceClienteCnpj(
        cliente: _clienteDaVenda(vendaAtual),
        venda: vendaAtual,
      );
      if (bloqueioCnpj != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bloqueioCnpj),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
      final bloqueioNfce =
          VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(vendaAtual);
      if (bloqueioNfce != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bloqueioNfce),
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
      setState(() => _posVendaProcessando = true);
      try {
        await _aguardarEntreDialogos();
        if (!mounted) return;
        await _emitirNfceParaVenda(venda);
        _atualizarPosVendaDoRepositorio();
        if (!mounted) return;
        final vendaAtual = _vendaPosCaixaAtualizada() ?? venda;
        if (_vendaComDocumentoPosCaixaObrigatorio(vendaAtual)) {
          await _encerrarPosVendaFiscal();
        }
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
      return;
    }

    if (acao == 'cupom') {
      setState(() => _posVendaProcessando = true);
      try {
        await _imprimirCupomNaoFiscalPosVenda(
          venda: venda,
          totalRecebido: sessao.totalRecebido,
          troco: sessao.troco,
        );
        _atualizarPosVendaDoRepositorio();
        if (!mounted) return;
        final vendaAtual = _vendaPosCaixaAtualizada() ?? venda;
        if (_vendaComDocumentoPosCaixaObrigatorio(vendaAtual)) {
          await _encerrarPosVendaFiscal();
        }
      } finally {
        if (mounted) setState(() => _posVendaProcessando = false);
      }
    }
  }

  Future<bool> _reprocessarBaixaEstoquePosFiscal(
    int vendaId, {
    String origem = 'nota fiscal',
  }) async {
    try {
      final repo = widget.vendaRepository;
      if (repo is VendaApiRepository) {
        await repo.reprocessarBaixaEstoqueDocumentoVendaRemoto(
          vendaId,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      } else {
        repo.reprocessarBaixaEstoqueDocumentoVenda(
          vendaId,
          permitirVendaSemEstoque: _permitirVendaSemEstoque,
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      CaixaFeedback.erro(
        context,
        'Falha ao reprocessar baixa de estoque: ${LanApiFeedback.mensagem(e)}',
      );
      return false;
    }
  }

  Future<UsuarioSistema> _resolverUsuarioSessaoParaNfe() async {
    final todos = await _usuarioRepository.listarTodos(); // policy-allow: usuario sessao NF-e
    for (final u in todos) {
      if (u.login == widget.usuarioLogado.login) return u;
    }
    return widget.usuarioLogado;
  }

  Future<void> _tentarBaixaEstoquePosNfe55Autorizada(int vendaId) async {
    final v = widget.vendaRepository.obterPorId(vendaId);
    if (v == null || v.estoqueBaixadoCupom) return;
    final nfe = widget.vendaRepository.obterNfe55AutorizadaPorVenda(vendaId);
    if (nfe == null) return;
    await _reprocessarBaixaEstoquePosFiscal(
      vendaId,
      origem: 'NF-e 55',
    );
    if (!mounted) return;
    final atualizado = widget.vendaRepository.obterPorId(vendaId);
    if (atualizado?.estoqueBaixadoCupom == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NF-e ${nfe.numero.isNotEmpty ? nfe.numero : nfe.referenciaFocus} '
            'vinculada — estoque atualizado.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _alertarVendaSemNfe55SeNecessario(Venda venda) async {
    final cliente = _clienteDaVenda(venda);
    if (!ClienteFiscalHelper.clienteExigeNfe55(cliente)) return;
    if (widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id) != null) {
      return;
    }
    if (!mounted) return;
    final r = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.description_outlined, color: Colors.orange.shade800),
        title: const Text('NF-e modelo 55 pendente'),
        content: Text(
          'A venda para ${cliente?.nomeRazao ?? 'cliente CNPJ'} foi finalizada '
          'sem NF-e autorizada.\n\n'
          'Construtoras e revendas costumam exigir NF-e 55. '
          'Abra o menu Notas fiscais → NF-e de saida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'emitir'),
            child: const Text('Emitir NF-e agora'),
          ),
        ],
      ),
    );
    if (!mounted || r != 'emitir') return;
    final usuarioNfe = await _resolverUsuarioSessaoParaNfe();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NfeGerenciamentoPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          appConfigRepository: widget.appConfigRepository,
          usuarioLogado: usuarioNfe,
          vendaIdInicial: venda.id,
        ),
      ),
    );
  }

  Future<void> _imprimirCupomNaoFiscalPosVenda({
    required Venda venda,
    required double totalRecebido,
    required double troco,
  }) async {
    try {
      widget.vendaRepository.registrarBaixaEstoqueCupomNaoFiscal(
        venda.id,
        permitirVendaSemEstoque: _permitirVendaSemEstoque,
      );
    } catch (e) {
      if (!mounted) return;
      CaixaFeedback.erro(
        context,
        'Nao foi possivel baixar estoque: ${LanApiFeedback.mensagem(e)}',
      );
      return;
    }
    final vendaAtualizada =
        widget.vendaRepository.obterPorId(venda.id) ?? venda;
    final cupomValores =
        CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom(vendaAtualizada);
    final recebidoImp = cupomValores.recebido > 0.009
        ? cupomValores.recebido
        : totalRecebido;
    final trocoImp =
        cupomValores.troco > 0.009 ? cupomValores.troco : troco;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    List<ItemVenda> itensCupom = const [];
    final repo = widget.vendaRepository;
    try {
      if (repo is VendaApiRepository) {
        itensCupom = await repo.carregarItensRemoto(vendaAtualizada.id);
      } else {
        itensCupom = List<ItemVenda>.from(
          repo.listarItensPorVenda(vendaAtualizada.id) as List,
        );
      }
    } catch (_) {
      itensCupom = _itensVenda(vendaAtualizada);
    }
    final nomeArquivo =
        'venda_${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Comprovante da venda',
      content: 'Deseja imprimir o comprovante agora ou gerar PDF?',
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: vendaAtualizada,
        config: config,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: recebidoImp,
        troco: trocoImp,
        segundaVia: false,
        dataCabecalhoVenda: DateTime.now(),
        itens: itensCupom,
      ),
      dadosEscPos: CupomBalcaoDados(
        venda: vendaAtualizada,
        config: config,
        itens: itensCupom,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: recebidoImp,
        troco: trocoImp,
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _aguardarEntreDialogos() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  EmitirNfceVendaDeps get _emitirNfceDeps => EmitirNfceVendaDeps(
        vendaRepository: widget.vendaRepository,
        clienteRepository: widget.clienteRepository,
        vendedorRepository: widget.vendedorRepository,
        produtoRepository: widget.produtoRepository,
        appConfigRepository: widget.appConfigRepository,
        printService: widget.printService,
        focusNfeService: _focusNfeService,
      );

  Future<void> _emitirNfceParaVenda(Venda venda) async {
    if (widget.vendaRepository is VendaApiRepository) {
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'API do servidor indisponivel para emitir NFC-e.',
            ),
          ),
        );
        return;
      }
      try {
        final r = await client.emitirNfce(venda.id);
        if (!mounted) return;
        if (r['ok'] == true) {
          await _aposMutacaoFiscalOuCancelamentoCaixa(vendaId: venda.id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                r['autorizada'] == true
                    ? 'NFC-e ${(r['numero'] ?? '').toString()} autorizada no servidor.'
                    : 'NFC-e em processamento no servidor.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${r['error'] ?? 'Falha ao emitir NFC-e'}'),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao emitir NFC-e');
      }
      return;
    }
    await EmitirNfceVendaFlow.executar(
      context,
      deps: _emitirNfceDeps,
      venda: venda,
      fluxoAutomaticoPosVenda: _documentoFiscalAutomaticoDisparado,
      onConcluidoComSucesso: () {
        _atualizarListaUltimasVendasFinalizadasCaixa();
        _atualizarResumoNfcePendenteEmissao();
      },
    );
  }

  Future<Venda?> _buscarVendaFinalizadaParaSegundaVia(int numeroOuId) async {
    final repo = widget.vendaRepository;
    final local = repo.buscarVendaFinalizadaPorNumeroOuId(numeroOuId);
    if (local != null) return local;
    if (repo is VendaApiRepository) {
      try {
        return await repo.buscarVendaFinalizadaPorNumeroOuIdRemoto(numeroOuId);
      } catch (e) {
        debugPrint('Caixa: busca 2a via remota: $e');
        return null;
      }
    }
    return null;
  }

  static const int _ultimasVendasFinalizadasLimite = 20;

  Future<void> _carregarOrdenacaoUltimasVendas() async {
    final prefs = await SharedPreferences.getInstance();
    final salva = UltimasVendasFinalizadasOrdenacao.fromChave(
      prefs.getString(_prefsOrdenacaoUltimasVendas),
    );
    if (!mounted) return;
    setState(() {
      _ordenacaoUltimasVendas =
          salva ?? UltimasVendasFinalizadasOrdenacao.padrao;
    });
    unawaited(_garantirCorrecaoFinalizadaEmLegado());
  }

  Future<void> _garantirCorrecaoFinalizadaEmLegado() async {
    if (_correcaoFinalizadaEmDisparada) return;
    _correcaoFinalizadaEmDisparada = true;
    final prefs = await SharedPreferences.getInstance();
    const chave = 'caixa_finalizada_em_corrigido_v2';
    if (prefs.getBool(chave) != true) {
      widget.vendaRepository.corrigirFinalizadaEmCopiadaDaDataOrcamento();
      await prefs.setBool(chave, true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _alterarOrdenacaoUltimasVendas(
    UltimasVendasFinalizadasOrdenacao ordenacao,
  ) async {
    if (_ordenacaoUltimasVendas == ordenacao) return;
    setState(() => _ordenacaoUltimasVendas = ordenacao);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsOrdenacaoUltimasVendas, ordenacao.chave);
  }

  List<Venda> _ultimasVendasFinalizadasParaCaixa() {
    return widget.vendaRepository.listarUltimasVendasFinalizadas(
      limit: _ultimasVendasFinalizadasLimite,
      ordenacao: _ordenacaoUltimasVendas,
    );
  }

  void _atualizarListaUltimasVendasFinalizadasCaixa() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _abrirAcoesVendaFinalizada(Venda vIn) async {
    // Autorizacao de 2a via so na acao "cupom" (nao bloqueia cancelar/NFC-e/DANFE).
    await _aguardarEntreDialogos();
    if (!mounted) return;
    final v = widget.vendaRepository.obterPorId(vIn.id) ?? vIn;
    if (!mounted) return;
    if (v.cancelada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao e possivel abrir acoes de venda cancelada.'),
        ),
      );
      return;
    }
    if (v.status != 'finalizada') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Acoes disponiveis apenas para vendas finalizadas.',
          ),
        ),
      );
      return;
    }

    final numCupom = v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id;
    final cliente = _clienteDaVenda(v);
    final nfceEmitida = v.nfceEmitida;
    final nfe55Autorizada = v.nfe55Autorizada;
    final bloqueiaNovaNfce = VendaDocumentoFiscalMutex.bloqueiaNovaNfce(v);
    final temDanfe = v.nfceUrlDanfe.trim().isNotEmpty;
    final temDanfeNfe55 = v.nfeUrlDanfe.trim().isNotEmpty;

    final acao = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Venda $numCupom'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total: ${_formatarMoeda(v.total)}'),
                Text(
                  'Cliente: ${cliente?.nomeRazao ?? 'Consumidor / sem cadastro'}',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      nfceEmitida
                          ? Icons.check_circle_outline
                          : Icons.receipt_long_outlined,
                      size: 20,
                      color: nfceEmitida
                          ? Colors.green.shade700
                          : Theme.of(ctx).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nfceEmitida
                            ? 'NFC-e ja emitida para esta venda.'
                            : 'NFC-e ainda nao emitida.',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (nfceEmitida) ...[
                  const SizedBox(height: 8),
                  if (v.nfceNumero.isNotEmpty)
                    Text('Numero NFC-e: ${v.nfceNumero}'),
                  if (v.nfceSerie.isNotEmpty) Text('Serie: ${v.nfceSerie}'),
                  if (v.nfceChaveAcesso.isNotEmpty)
                    Text(
                      'Chave: ${v.nfceChaveAcesso}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (v.nfceEmitidaEm != null)
                    Text(
                      'Emitida em: ${DateFormat('dd/MM/yyyy HH:mm').format(v.nfceEmitidaEm!.toLocal())}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  if (!temDanfe)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Link do DANFE nao foi salvo nesta venda.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade800,
                            ),
                      ),
                    ),
                ],
                if (nfe55Autorizada) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'NF-e modelo 55 ja emitida para esta venda.',
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  if (v.nfeNumero.isNotEmpty)
                    Text('Numero NF-e: ${v.nfeNumero}'),
                  if (v.nfeChaveAcesso.isNotEmpty)
                    Text(
                      'Chave: ${v.nfeChaveAcesso}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                ],
                if (!nfceEmitida && nfe55Autorizada) ...[
                  const SizedBox(height: 8),
                  Text(
                    'NFC-e nao pode ser emitida: esta venda ja possui NF-e.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cancelar'),
              icon: Icon(Icons.cancel_outlined, color: Theme.of(ctx).colorScheme.error),
              label: Text(
                'Cancelar venda',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cupom'),
              icon: const Icon(Icons.receipt_outlined),
              label: const Text('Segunda via cupom'),
            ),
            if (!bloqueiaNovaNfce)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'nfce'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Emitir NFC-e'),
              ),
            if (nfceEmitida && temDanfe)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'danfe_nfce'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Visualizar/Reimprimir DANFE NFC-e'),
              ),
            if (nfe55Autorizada && temDanfeNfe55)
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'danfe_nfe'),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Visualizar/Reimprimir DANFE NF-e'),
              ),
          ],
        );
      },
    );
    if (!mounted || acao == null) return;

    if (acao == 'cancelar') {
      await _cancelarVendaNoCaixa(v);
      return;
    }
    if (acao == 'cupom') {
      final autorizado = await autorizarSegundaViaCupomSeConfigurado(
        context: context,
        usuarioRepository: _usuarioRepository,
        exigirAutorizacao: _exigirAutorizacaoSegundaViaCupom,
      );
      if (!mounted || !autorizado) return;
      await _emitirSegundaViaCupomParaVenda(v);
    } else if (acao == 'nfce') {
      await _aguardarEntreDialogos();
      if (!mounted) return;
      await _emitirNfceParaVenda(v);
    } else if (acao == 'danfe_nfce') {
      await _abrirDanfeNfceVenda(v);
    } else if (acao == 'danfe_nfe') {
      await _abrirDanfeNfe55Venda(v);
    }
  }

  Future<void> _emitirSegundaViaCupomParaVenda(Venda v) async {
    final vendaAtualizada = widget.vendaRepository.obterPorId(v.id) ?? v;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (!mounted) return;
    List<ItemVenda> itensCupom = const [];
    final repo = widget.vendaRepository;
    try {
      if (repo is VendaApiRepository) {
        itensCupom = await repo.carregarItensRemoto(vendaAtualizada.id);
      } else {
        itensCupom = List<ItemVenda>.from(
          repo.listarItensPorVenda(vendaAtualizada.id) as List,
        );
      }
    } catch (_) {
      itensCupom = _itensVenda(vendaAtualizada);
    }
    if (itensCupom.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nao foi possivel carregar os itens desta venda para o PDF.',
          ),
        ),
      );
      return;
    }
    final infer = CupomNaoFiscalVendaPdf.recebidoTrocoParaCupom(vendaAtualizada);
    final nomeArquivo =
        'venda_${vendaAtualizada.numeroOrcamento > 0 ? vendaAtualizada.numeroOrcamento : vendaAtualizada.id}_2via.pdf';
    await mostrarFluxoImpressaoCupomVenda(
      context,
      printService: widget.printService,
      config: config,
      title: 'Segunda via do cupom',
      content: 'Deseja imprimir ou gerar PDF da segunda via?',
      gerarPdf: () => CupomNaoFiscalVendaPdf.gerar(
        venda: vendaAtualizada,
        config: config,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
        dataCabecalhoVenda: vendaAtualizada.data,
        itens: itensCupom,
      ),
      dadosEscPos: CupomBalcaoDados(
        venda: vendaAtualizada,
        config: config,
        itens: itensCupom,
        cliente: _clienteDaVenda(vendaAtualizada),
        vendedor: _vendedorDaVenda(vendaAtualizada),
        totalRecebido: infer.recebido,
        troco: infer.troco,
        segundaVia: true,
      ),
      suggestedFileName: nomeArquivo,
    );
  }

  Future<void> _abrirDanfeNfceVenda(Venda venda) async {
    await abrirDanfeFocus(
      context,
      focusNfe: _focusNfeService,
      urlSalva: venda.nfceUrlDanfe,
      venda: venda,
    );
  }

  Future<void> _abrirDanfeNfe55Venda(Venda venda) async {
    final reg = widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id);
    final url = reg?.urlDanfe.trim().isNotEmpty == true
        ? reg!.urlDanfe
        : venda.nfeUrlDanfe.trim().isNotEmpty
            ? venda.nfeUrlDanfe
            : (reg?.urlXml ?? '');
    await abrirUrlDocumentoFiscal(
      context,
      url,
      mensagemSeVazio: 'NF-e autorizada, mas sem link de DANFE/XML salvo.',
    );
  }

  Future<void> _confirmarSegundaViaPorNumero(
    BuildContext dialogContext,
    String texto,
  ) async {
    final n = int.tryParse(texto.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(content: Text('Digite um numero valido.')),
      );
      return;
    }
    final v = await _buscarVendaFinalizadaParaSegundaVia(n);
    if (!dialogContext.mounted) return;
    if (v == null) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Venda nao encontrada, cancelada ou ainda nao finalizada.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(dialogContext, v);
  }

  Future<void> _abrirSegundaViaCupom() async {
    final numeroController = TextEditingController();
    final encontrada = await showDialog<Venda>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Segunda via do cupom'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informe o numero da venda no cupom ou o ID interno.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numeroController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numero da venda ou ID',
                    hintText: 'Ex.: 1042',
                  ),
                  onSubmitted: (_) => unawaited(_confirmarSegundaViaPorNumero(
                    ctx,
                    numeroController.text,
                  )),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => unawaited(_confirmarSegundaViaPorNumero(
                ctx,
                numeroController.text,
              )),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    numeroController.dispose();
    if (!mounted || encontrada == null) return;
    await _abrirAcoesVendaFinalizada(encontrada);
  }

  Future<bool?> _mostrarResumoFechamentoVenda({
    required int numeroOrcamento,
    required String textoPagamento,
    String? textoPlanoFiado,
    required double totalVenda,
    required double descontoAplicado,
    required double totalRecebido,
    required double troco,
    required int quantidadeItens,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DialogoResumoFechamentoVenda(
        numeroOrcamento: numeroOrcamento,
        textoPagamento: textoPagamento,
        textoPlanoFiado: textoPlanoFiado,
        totalVenda: totalVenda,
        descontoAplicado: descontoAplicado,
        totalRecebido: totalRecebido,
        troco: troco,
        quantidadeItens: quantidadeItens,
        formatarMoeda: _formatarMoeda,
        buildResumoCard: _buildResumoCard,
      ),
    );
  }

  Future<int?> _abrirCadastroNovoCliente() async {
    final cliente = await Navigator.push<Cliente>(
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
    if (!mounted || cliente == null) return null;
    return cliente.id;
  }

  Future<void> _vincularClienteAgora() async {
    final venda = _selecionado;
    if (venda == null) return;
    int? clienteSelecionadoId = venda.cliente.targetId > 0
        ? venda.cliente.targetId
        : null;
    final pesquisaClienteController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        var clientesExibidos = widget.clienteRepository.listarPaginado(
          limit: 60,
          somenteAtivos: true,
        );
        Timer? debounceApi;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void atualizarBusca(String termo) {
              final t = termo.trim();
              setDialogState(() {
                clientesExibidos = t.isEmpty
                    ? widget.clienteRepository.listarPaginado(
                        limit: 60,
                        somenteAtivos: true,
                      )
                    : widget.clienteRepository
                        .pesquisar(t)
                        .where((c) => c.ativo)
                        .take(60)
                        .toList();
              });
              final repo = widget.clienteRepository;
              if (repo is! ClienteApiRepository || t.isEmpty) return;
              debounceApi?.cancel();
              debounceApi = Timer(const Duration(milliseconds: 320), () async {
                try {
                  final remotos = await repo.pesquisarRemoto(t, limit: 60);
                  if (!context.mounted) return;
                  setDialogState(() {
                    clientesExibidos =
                        remotos.where((c) => c.ativo).take(60).toList();
                  });
                } catch (_) {}
              });
            }

            return AlertDialog(
              title: const Text('Vincular cliente ao orcamento'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final novoId = await _abrirCadastroNovoCliente();
                        if (novoId == null) return;
                        setDialogState(() {
                          clienteSelecionadoId = novoId;
                          clientesExibidos = [
                            widget.clienteRepository.obterPorId(novoId),
                          ].whereType<Cliente>().toList();
                        });
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cliente cadastrado. Toque Salvar para vincular ao orcamento.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Cadastrar novo cliente'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pesquisaClienteController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar cliente',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: atualizarBusca,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      selected: clienteSelecionadoId == null,
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Sem cliente'),
                      onTap: () => setDialogState(() => clienteSelecionadoId = null),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: clientesExibidos.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Nenhum cliente. Digite para buscar ou cadastre um novo.',
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: clientesExibidos.length,
                              itemBuilder: (context, index) {
                                final c = clientesExibidos[index];
                                return ListTile(
                                  dense: true,
                                  selected: clienteSelecionadoId == c.id,
                                  title: Text(c.nomeRazao),
                                  subtitle: c.documento.trim().isEmpty
                                      ? null
                                      : Text(c.documento),
                                  onTap: () => setDialogState(
                                    () => clienteSelecionadoId = c.id,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaClienteController.dispose();
    if (confirmar != true) return;
    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .vincularClienteNoOrcamentoRemoto(
          venda.id,
          clienteSelecionadoId,
        );
      } else {
        widget.vendaRepository.vincularClienteNoOrcamento(
          venda.id,
          clienteSelecionadoId,
        );
      }
      _carregarOrcamentos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente atualizado no orcamento.')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Nao foi possivel vincular cliente',
      );
    }
  }

  Future<void> _vincularVendedorAgora() async {
    final venda = _selecionado;
    if (venda == null) return;
    if (_vendedorDaVenda(venda) != null) return;

    final vendedoresAtivos = widget.vendedorRepository.listarAtivos();
    if (vendedoresAtivos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum vendedor ativo cadastrado. Cadastre em Cadastros → Vendedores.',
          ),
        ),
      );
      return;
    }

    int? vendedorSelecionadoId = vendedoresAtivos.length == 1
        ? vendedoresAtivos.first.id
        : null;
    final pesquisaController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        var vendedoresExibidos = vendedoresAtivos.take(60).toList();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void atualizarBusca(String termo) {
              final t = termo.trim();
              setDialogState(() {
                vendedoresExibidos = t.isEmpty
                    ? vendedoresAtivos.take(60).toList()
                    : widget.vendedorRepository
                        .pesquisar(t)
                        .where((v) => v.ativo)
                        .take(60)
                        .toList();
              });
            }

            return AlertDialog(
              title: const Text('Vincular vendedor ao orcamento'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Orcamento ${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id} '
                      'sem vendedor no PDV.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pesquisaController,
                      decoration: const InputDecoration(
                        labelText: 'Buscar vendedor',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: atualizarBusca,
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: vendedoresExibidos.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('Nenhum vendedor encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: vendedoresExibidos.length,
                              itemBuilder: (context, index) {
                                final v = vendedoresExibidos[index];
                                final nome = v.apelido.trim().isNotEmpty
                                    ? v.apelido.trim()
                                    : v.nomeCompleto.trim();
                                final codigo = v.codigoInterno.trim();
                                return ListTile(
                                  dense: true,
                                  selected: vendedorSelecionadoId == v.id,
                                  title: Text(nome),
                                  subtitle: codigo.isEmpty ? null : Text(codigo),
                                  onTap: () => setDialogState(
                                    () => vendedorSelecionadoId = v.id,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: vendedorSelecionadoId == null
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    pesquisaController.dispose();
    if (confirmar != true || vendedorSelecionadoId == null) return;
    final vendedorId = vendedorSelecionadoId!;
    try {
      if (widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .vincularVendedorNoOrcamentoRemoto(venda.id, vendedorId);
      } else {
        widget.vendaRepository.vincularVendedorNoOrcamento(
          venda.id,
          vendedorId,
        );
      }
      _carregarOrcamentos();
      if (!mounted) return;
      final v = widget.vendedorRepository.obterPorId(vendedorId);
      final nome = v == null
          ? 'Vendedor $vendedorId'
          : _rotuloVendedorUmLinha(
              widget.vendaRepository.obterPorId(venda.id) ?? venda,
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vendedor vinculado: $nome')),
      );
    } catch (e) {
      if (!mounted) return;
      LanApiFeedback.snackErro(
        context,
        e,
        prefixo: 'Nao foi possivel vincular vendedor',
      );
    }
  }

  /// Barra compacta de acoes quando nenhum orcamento esta selecionado.
  Widget _buildBarraAcoesIniciaisCaixa(BuildContext context) {
    final outlinedCompact = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final filledCompact = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    Widget botao({
      required String rotulo,
      required String dica,
      required IconData icone,
      required VoidCallback? onPressed,
      required bool destaque,
    }) {
      final filho = destaque
          ? FilledButton.tonalIcon(
              style: filledCompact,
              onPressed: onPressed,
              icon: Icon(icone, size: 20),
              label: Text(rotulo),
            )
          : OutlinedButton.icon(
              style: outlinedCompact,
              onPressed: onPressed,
              icon: Icon(icone, size: 20),
              label: Text(rotulo),
            );
      return Tooltip(message: dica, child: filho);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final estreito = constraints.maxWidth < 400;
        final rotuloImportar = estreito
            ? 'Importar (F1)'
            : 'Importar Orçamento (F1)';

        Widget importar() => botao(
              rotulo: rotuloImportar,
              dica: 'Pesquisar orcamento para importar (F1)',
              icone: Icons.search,
              onPressed: _abrirPesquisaOrcamento,
              destaque: false,
            );
        Widget segundaVia() => botao(
              rotulo: '2a via (F2)',
              dica: 'Segunda via da nota (F2)',
              icone: Icons.receipt_long_outlined,
              onPressed: _abrirSegundaViaCupom,
              destaque: false,
            );
        Widget fiado() => botao(
              rotulo: 'Fiado (F3)',
              dica: 'Receber fiado (F3)',
              icone: Icons.payments_outlined,
              onPressed: _caixaAberto ? _abrirReceberFiado : null,
              destaque: true,
            );

        if (estreito) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: importar()),
                  const SizedBox(width: 8),
                  Expanded(child: segundaVia()),
                ],
              ),
              const SizedBox(height: 8),
              fiado(),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: importar()),
            const SizedBox(width: 8),
            Expanded(child: segundaVia()),
            const SizedBox(width: 8),
            Expanded(child: fiado()),
          ],
        );
      },
    );
  }

  Widget _buildEtapaFila(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaixaImportarOrcamentoField(
          controller: _importarOrcamentoController,
          focusNode: _importarOrcamentoFocus,
          habilitado: _caixaAberto,
          onImportar: (n) => unawaited(_importarOrcamentoPorNumero(n)),
          onAbrirPesquisa: () => unawaited(_abrirPesquisaOrcamento()),
        ),
        const SizedBox(height: 8),
        _buildBarraAcoesIniciaisCaixa(context),
        const SizedBox(height: 10),
        Expanded(child: _buildPainelStatusCaixa(context)),
      ],
    );
  }

  Widget _buildTabelaItensConferencia(
    BuildContext context,
    Venda selecionado,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final itens = _itensVenda(selecionado);
    final podeRemover = itens.length > 1;

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 4,
                  child: Text('Produto', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 132,
                  child: Text(
                    'Qtd',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text('Vlr Unit', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: Text(
                    'Total',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 44),
              ],
            ),
          ),
          Expanded(
            child: RawScrollbar(
              controller: _itensScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 10,
              radius: const Radius.circular(8),
              child: ListView.builder(
                controller: _itensScrollController,
                padding: const EdgeInsets.only(right: 10),
                itemCount: itens.length,
                itemBuilder: (context, index) {
                  final item = itens[index];
                  final produto = _produtoDoItem(item);
                  final passoQtd = ProdutoEmbalagem.passoQuantidadeArmazenada(
                    produto: produto,
                    quantidadeArmazenada: item.quantidade,
                  );
                  final qtdTexto = ProdutoEmbalagem.textoQuantidadeArmazenada(
                    produto: produto,
                    quantidadeArmazenada: item.quantidade,
                  );
                  final noMinimo = item.quantidade <= passoQtd;
                  final fundoTipo = PdvBotaoTipoEntregaItem.fundoPara(
                    context,
                    item.tipoEntregaItem,
                  );
                  final bordaTipo = PdvBotaoTipoEntregaItem.bordaPara(
                    context,
                    item.tipoEntregaItem,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Material(
                      color: fundoTipo,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: bordaTipo, width: 4),
                            bottom: BorderSide(
                              color: bordaTipo.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                child: Text('${index + 1}'),
                              ),
                              Expanded(
                                flex: 4,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.nomeProduto,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    PdvBotaoTipoEntregaItem(
                                      tipoEntregaItem: item.tipoEntregaItem,
                                      compacto: true,
                                      onPressed: () => unawaited(
                                        _alternarTipoEntregaItemConferencia(
                                          selecionado,
                                          item,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 168,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      tooltip: noMinimo
                                          ? 'Remover item'
                                          : 'Diminuir quantidade',
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: noMinimo
                                          ? (podeRemover
                                              ? () => unawaited(
                                                    _removerItemConferencia(
                                                      selecionado,
                                                      item,
                                                    ),
                                                  )
                                              : null)
                                          : () => unawaited(
                                                _alterarQuantidadeItemConferencia(
                                                  selecionado,
                                                  item,
                                                  -1,
                                                ),
                                              ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        qtdTexto,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 36,
                                        minHeight: 36,
                                      ),
                                      tooltip: 'Aumentar quantidade',
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed: () => unawaited(
                                        _alterarQuantidadeItemConferencia(
                                          selecionado,
                                          item,
                                          1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _formatarMoeda(item.precoUnitario),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _formatarMoeda(_subtotalLinhaItem(item)),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  tooltip: podeRemover
                                      ? 'Remover item (gerente)'
                                      : 'Ultimo item — nao pode remover',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: podeRemover
                                        ? scheme.error
                                        : scheme.onSurface.withValues(
                                            alpha: 0.3,
                                          ),
                                  ),
                                  onPressed: podeRemover
                                      ? () => unawaited(
                                            _removerItemConferencia(
                                              selecionado,
                                              item,
                                            ),
                                          )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rodape fixo da conferencia: pagamento + total em destaque (padrao PDV).
  Widget _buildRodapeConferenciaPagamentoTotal(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
    required double descontoCaixa,
  }) {
    return CaixaRodapeTotalDestaque(
      tituloSecaoPagamento: 'Pagamento previsto',
      rotuloPagamento: _rotuloPagamentoCabecalho(selecionado),
      totalFormatado: _formatarMoeda(totalComDesconto),
      formatarMoeda: _formatarMoeda,
      descontoPdvOrcamento: descontoPdvOrcamento,
      descontoCaixa: descontoCaixa,
      onDesconto: _descontoCaixaDisponivel()
          ? () => unawaited(_abrirDescontoCaixa())
          : null,
    );
  }

  Widget _buildEtapaConferencia(
    BuildContext context, {
    required Venda selecionado,
    required Cliente? clienteSelecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
    required double descontoCaixa,
    required List<PagamentoOrcamentoLinha> linhasMistoCaixa,
    required double valorTotalRecebidoCard,
    required double troco,
  }) {
    final painel = _painelCobrancaAberto
        ? _buildPainelCobrancaLateral(
            context,
            selecionado: selecionado,
            totalComDesconto: totalComDesconto,
            descontoPdvOrcamento: descontoPdvOrcamento,
            descontoCaixa: descontoCaixa,
            linhasMistoCaixa: linhasMistoCaixa,
            valorTotalRecebidoCard: valorTotalRecebidoCard,
            troco: troco,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbarOrcamentoAtivo(
          context,
          selecionado: selecionado,
          clienteSelecionado: clienteSelecionado,
          incluirBuscaProduto: !_painelCobrancaAberto,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final empilhar = constraints.maxWidth < 780;
              if (empilhar) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: _painelCobrancaAberto ? 3 : 1,
                      child: _buildTabelaItensConferencia(context, selecionado),
                    ),
                    if (painel != null) ...[
                      const SizedBox(height: 8),
                      Expanded(flex: 2, child: painel),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildTabelaItensConferencia(
                            context,
                            selecionado,
                          ),
                        ),
                        if (!_painelCobrancaAberto)
                          _buildRodapeConferenciaAcao(
                            context,
                            selecionado: selecionado,
                            totalComDesconto: totalComDesconto,
                            descontoPdvOrcamento: descontoPdvOrcamento,
                            descontoCaixa: descontoCaixa,
                          ),
                      ],
                    ),
                  ),
                  if (painel != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 380, child: painel),
                  ],
                ],
              );
            },
          ),
        ),
        if (_painelCobrancaAberto && MediaQuery.sizeOf(context).width < 780)
          const SizedBox(height: 8),
        if (!_painelCobrancaAberto && MediaQuery.sizeOf(context).width < 780)
          _buildRodapeConferenciaAcao(
            context,
            selecionado: selecionado,
            totalComDesconto: totalComDesconto,
            descontoPdvOrcamento: descontoPdvOrcamento,
            descontoCaixa: descontoCaixa,
          ),
      ],
    );
  }

  Widget _buildPainelCobrancaLateral(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double descontoPdvOrcamento,
    required double descontoCaixa,
    required List<PagamentoOrcamentoLinha> linhasMistoCaixa,
    required double valorTotalRecebidoCard,
    required double troco,
  }) {
    return CaixaPainelCobrancaLateral(
      rotuloPagamento: _rotuloPagamentoCabecalho(selecionado),
      totalComDesconto: totalComDesconto,
      descontoPdvOrcamento: descontoPdvOrcamento,
      descontoCaixa: descontoCaixa,
      formatarMoeda: _formatarMoeda,
      recebimento: _buildCorpoRecebimentoCobranca(
        context,
        selecionado: selecionado,
        totalComDesconto: totalComDesconto,
        troco: troco,
        linhasMistoCaixa: linhasMistoCaixa,
      ),
      valorRecebidoExibicao: valorTotalRecebidoCard,
      troco: troco,
      onAlterarForma: () => _alterarFormaPagamentoCaixa(selecionado),
      onDesconto: _descontoCaixaDisponivel()
          ? () => unawaited(_abrirDescontoCaixa())
          : null,
      onFechar: _finalizandoVenda ? null : _fecharPainelCobranca,
      onFinalizar: _finalizandoVenda
          ? null
          : () => unawaited(_finalizarOrcamento(selecionado)),
    );
  }

  Widget _buildCorpoRecebimentoCobranca(
    BuildContext context, {
    required Venda selecionado,
    required double totalComDesconto,
    required double troco,
    required List<PagamentoOrcamentoLinha> linhasMistoCaixa,
  }) {
    if (selecionado.formaPagamento == 'misto' && linhasMistoCaixa.isNotEmpty) {
      return _buildPainelPagamentosMistoNoCaixa(
        context,
        venda: selecionado,
        totalComDesconto: totalComDesconto,
      );
    }

    if (_caixaPrecisaValorRecebidoDinheiro(selecionado)) {
      final parteDinheiro =
          _parteDinheiroNaFinalizacao(selecionado, totalComDesconto);
      return CaixaCobrancaCampoDinheiro(
        controller: _valorRecebidoController,
        focusNode: _valorRecebidoFocusNode,
        totalAPagar: parteDinheiro > 0.001 ? parteDinheiro : totalComDesconto,
        troco: troco,
        formatarMoeda: _formatarMoeda,
        onChanged: (value) {
          setState(() => _valorRecebido = _parseValor(value));
        },
        onSubmitted: (_) => unawaited(_finalizarOrcamento(selecionado)),
      );
    }

    final forma = selecionado.formaPagamento;
    final planoFiado = PlanoFiadoCodec.decode(selecionado.planoFiadoJson);
    var detalhe = '';
    if (forma == 'fiado' && planoFiado.isNotEmpty) {
      detalhe = PlanoFiadoCodec.formatarResumoLinhas(planoFiado);
    }

    return CaixaCobrancaConfirmacaoSimples(
      icone: _iconeFormaPagamentoCaixa(forma),
      titulo: _rotuloFormaPagamento(forma),
      subtitulo:
          'Confirme o recebimento de ${_formatarMoeda(totalComDesconto)} '
          'e pressione Enter para finalizar.',
      detalhe: detalhe.isEmpty ? null : detalhe,
    );
  }

  IconData _iconeFormaPagamentoCaixa(String forma) => switch (forma) {
        'dinheiro' => Icons.payments_outlined,
        'pix' => Icons.qr_code_2_outlined,
        'cartao_credito' || 'cartao_debito' => Icons.credit_card_outlined,
        'fiado' => Icons.receipt_long_outlined,
        'misto' => Icons.account_balance_wallet_outlined,
        _ => Icons.point_of_sale_outlined,
      };

  Widget _buildEtapaFiscal(BuildContext context) {
    final sessao = _posVenda;
    if (sessao == null) {
      return _buildEtapaFila(context);
    }
    final venda = sessao.venda;
    final cliente = _clienteDaVenda(venda);
    final exigeNfe55 = ClienteFiscalHelper.clienteExigeNfe55(cliente);
    final jaTemNfe55 =
        widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id) != null;
    final vendaAtual = _vendaPosCaixaAtualizada() ?? venda;
    final podeConcluir = _vendaComDocumentoPosCaixaObrigatorio(vendaAtual);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CaixaPosVendaFiscalPainel(
            venda: vendaAtual,
            cliente: cliente,
            totalRecebido: sessao.totalRecebido,
            troco: sessao.troco,
            formatarMoeda: _formatarMoeda,
            exigeNfe55: exigeNfe55,
            jaTemNfe55: jaTemNfe55,
            podeConcluir: podeConcluir,
            processando: _posVendaProcessando,
            acaoFiscalSugerida:
                _acaoFiscalAutomaticaPorPagamento(vendaAtual),
            onCupomNaoFiscal: () => unawaited(_executarAcaoPosVendaFiscal('cupom')),
            onEmitirNfce: () => unawaited(_executarAcaoPosVendaFiscal('nfce')),
            onEmitirNfe55: () => unawaited(_executarAcaoPosVendaFiscal('nfe55')),
            bloqueiaNovaNfce: _bloqueiaNovaNfceNoCaixa(vendaAtual),
            onConcluir: () => unawaited(_encerrarPosVendaFiscal()),
            onCancelarVenda: () =>
                unawaited(_cancelarVendaNoCaixa(venda)),
          ),
        ),
      ],
    );
  }

  Widget _buildCorpoCaixa(BuildContext context) {
    if (_etapaCaixa == CaixaEtapa.fiscal && _posVenda != null) {
      return _buildEtapaFiscal(context);
    }

    if (_selecionado == null) {
      if (_etapaCaixa != CaixaEtapa.fila) {
        _etapaCaixa = CaixaEtapa.fila;
      }
      return _buildEtapaFila(context);
    }

    final selecionado = _selecionado!;
    final clienteSelecionado = _clienteDaVenda(selecionado);
    final descontoSelecionado = _descontoAplicado(selecionado);
    final totalComDesconto = _totalComDesconto(selecionado);
    final descontoPdvOrcamento = _descontoPdvOrcamentoExibicao(selecionado);
    final descontoCaixa = descontoSelecionado;
    final parteDinheiroResumo =
        _parteDinheiroNaFinalizacao(selecionado, totalComDesconto);
    final linhasMistoCaixa = selecionado.formaPagamento == 'misto'
        ? (_mistoValorControllers.isNotEmpty
            ? _linhasMistoDoFormulario()
            : _linhasPagamentoEscaladasCaixa(selecionado, totalComDesconto))
        : <PagamentoOrcamentoLinha>[];
    final somaMistoCaixa = linhasMistoCaixa.isEmpty
        ? 0.0
        : PagamentoOrcamentoCodec.soma(linhasMistoCaixa);
    final troco = selecionado.formaPagamento == 'misto'
        ? (somaMistoCaixa - totalComDesconto).clamp(0.0, double.infinity).toDouble()
        : (parteDinheiroResumo > 0.001
            ? ((_valorRecebido ?? 0) - parteDinheiroResumo)
                .clamp(0, double.infinity)
                .toDouble()
            : 0.0);
    final valorTotalRecebidoCard = selecionado.formaPagamento == 'misto' &&
            linhasMistoCaixa.isNotEmpty
        ? somaMistoCaixa
        : (_caixaPrecisaValorRecebidoDinheiro(selecionado)
            ? (_valorRecebido ?? 0)
            : totalComDesconto);

    switch (_etapaCaixa) {
      case CaixaEtapa.fiscal:
        return _buildEtapaFiscal(context);
      case CaixaEtapa.cobranca:
      case CaixaEtapa.fila:
      case CaixaEtapa.conferencia:
        return _buildEtapaConferencia(
          context,
          selecionado: selecionado,
          clienteSelecionado: clienteSelecionado,
          totalComDesconto: totalComDesconto,
          descontoPdvOrcamento: descontoPdvOrcamento,
          descontoCaixa: descontoCaixa,
          linhasMistoCaixa: linhasMistoCaixa,
          valorTotalRecebidoCard: valorTotalRecebidoCard,
          troco: troco,
        );
    }
  }

  @override
  void dispose() {
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    LanApiEventHub.instance.removeListener(_onApiEntityChanged);
    CaixaLocalRefreshHub.instance.removeListener(_onCaixaLocalRefresh);
    _debounceSyncOrcamentos?.cancel();
    HardwareKeyboard.instance.removeHandler(_handlerTeclasHardwareCaixa);
    _timerReconciliacaoNfce?.cancel();
    _valorRecebidoController.dispose();
    _valorRecebidoFocusNode.dispose();
    _focusAtalhosCaixa.dispose();
    _itensScrollController.dispose();
    _pesquisaProdutoConferenciaController.dispose();
    _pesquisaProdutoConferenciaFocus.dispose();
    _importarOrcamentoController.dispose();
    _importarOrcamentoFocus.dispose();
    _disposeMistoEdicao();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.f1): const _ImportarOrcamentoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f2): const _SegundaViaCupomIntent(),
        LogicalKeySet(LogicalKeyboardKey.f3): const _ReceberFiadoIntent(),
        LogicalKeySet(LogicalKeyboardKey.f4): const _VincularClienteIntent(),
        LogicalKeySet(LogicalKeyboardKey.f5): const _BuscarProdutoConferenciaIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ImportarOrcamentoIntent:
              CallbackAction<_ImportarOrcamentoIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              _abrirPesquisaOrcamento();
              return null;
            },
          ),
          _SegundaViaCupomIntent: CallbackAction<_SegundaViaCupomIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              _abrirSegundaViaCupom();
              return null;
            },
          ),
          _ReceberFiadoIntent: CallbackAction<_ReceberFiadoIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              if (!_caixaAberto) return null;
              _abrirReceberFiado();
              return null;
            },
          ),
          _VincularClienteIntent: CallbackAction<_VincularClienteIntent>(
            onInvoke: (intent) {
              if (ModalRoute.of(context)?.isCurrent != true) {
                return null;
              }
              if (_conferenciaAtivaComOrcamento()) {
                _vincularClienteAgora();
              }
              return null;
            },
          ),
          _BuscarProdutoConferenciaIntent:
              CallbackAction<_BuscarProdutoConferenciaIntent>(
            onInvoke: (intent) {
              if (!_atalhoCaixaAtivo()) return null;
              if (_etapaCaixa != CaixaEtapa.conferencia ||
                  _selecionado == null) {
                return null;
              }
              unawaited(_abrirConsultaProdutoConferencia());
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusAtalhosCaixa,
          autofocus: true,
          onKeyEvent: _tratarTeclaCaixaWizard,
          child: Scaffold(
            appBar: AppBar(
              title: _buildTituloAppBarCaixa(context),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Center(child: _buildChipNfcePendenteEmissao(context)),
                ),
                ContaSessaoAppBarActions(
                  login: widget.usuarioAtual,
                  onLogout: widget.onLogout,
                ),
              ],
            ),
            body: Stack(
              children: [
                Container(
                  color: theme.colorScheme.surfaceContainerLowest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (LanApiEventHub.instance.deveBloquearOperacoes)
                        Material(
                          color: theme.colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    LanApiEventHub.msgServidorOffline,
                                    style: TextStyle(
                                      color: theme.colorScheme.onErrorContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: _buildCorpoCaixa(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_finalizandoVenda)
                  const ModalBarrier(
                    dismissible: false,
                    color: Color(0x66000000),
                  ),
                if (_finalizandoVenda)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 22,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Processando finalizacao...',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Aguardando resposta do servidor.\nNao feche a tela.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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

  Future<bool?> _perguntarAbrirCaixaParaContinuar() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caixa fechado'),
        content: const Text(
          'Nao ha caixa aberto na loja. Deseja abrir agora para importar '
          'orcamentos e finalizar vendas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abrir caixa'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAvisosCaixasRemotos(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    if (_caixaAberto) {
      final origem = _caixaAderidoRemoto
          ? (_terminalSessaoAbertaId.isNotEmpty
              ? _terminalSessaoAbertaId
              : 'outro terminal')
          : 'neste PC';
      final abertura = _aberturaCaixaEm == null
          ? ''
          : ' · desde ${DateFormat('HH:mm').format(_aberturaCaixaEm!.toLocal())}';
      final abertos = _sessoesRede.values.where((s) => s.aberto).length;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_open_outlined,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Caixa aberto'
                      '${_operadorCaixa.trim().isNotEmpty ? ' · $_operadorCaixa' : ''}'
                      ' · $origem$abertura'
                      '${abertos > 0 ? ' · $abertos na loja' : ''}'
                      '${_caixaAderidoRemoto ? ' (aderido)' : ''}'
                      '${_umCaixaPorLojaRemoto && abertos <= 1 ? '' : (!_umCaixaPorLojaRemoto ? ' · multi-caixa' : '')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (_caixaApi != null) {
      final abertosRede =
          _sessoesRede.values.where((s) => s.aberto).toList(growable: false);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: abertosRede.isNotEmpty
                ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    abertosRede.isNotEmpty
                        ? Icons.warning_amber_outlined
                        : Icons.lock_outline,
                    size: 18,
                    color: abertosRede.isNotEmpty
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      abertosRede.isNotEmpty
                          ? 'Operacao bloqueada neste terminal, mas ha caixa '
                              'aberto na rede (${abertosRede.map((s) => s.terminalId).join(', ')}). '
                              'Com "um caixa por loja", recarregue a tela ou abra o Caixa novamente.'
                          : 'Caixa fechado na loja. Abra o caixa para importar orcamentos.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: abertosRede.isNotEmpty
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
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

    final outros = _sessoesRede.values
        .where((s) => s.aberto && s.terminalId != _terminalId)
        .toList();
    for (final s in outros) {
      if (_caixaAderidoRemoto && s.terminalId == _terminalSessaoAbertaId) {
        continue;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.cloud_sync_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Rede: caixa aberto em ${s.terminalId}'
                  '${s.operador.trim().isNotEmpty ? ' (${s.operador})' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildTituloAppBarCaixa(BuildContext context) {
    final selecionado = _selecionado;
    if (selecionado != null && _etapaCaixa != CaixaEtapa.fila) {
      final num = selecionado.numeroOrcamento > 0
          ? selecionado.numeroOrcamento
          : selecionado.id;
      final etapa = switch (_etapaCaixa) {
        CaixaEtapa.conferencia =>
          _painelCobrancaAberto ? 'Conferencia · Cobranca' : 'Conferencia',
        CaixaEtapa.cobranca => 'Conferencia · Cobranca',
        CaixaEtapa.fiscal => 'Fiscal',
        CaixaEtapa.fila => '',
      };
      return Text('Caixa · $etapa · Orc. $num');
    }
    final titulo = _caixaAberto ? 'Caixa' : 'Caixa · Fechado';
    if (_ultimoTrocoValor > 0.001 && _ultimoTrocoVendaId != null) {
      final num = _ultimoTrocoNumeroOrcamento > 0
          ? _ultimoTrocoNumeroOrcamento
          : _ultimoTrocoVendaId;
      final scheme = Theme.of(context).colorScheme;
      final texto = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(titulo),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Troco · venda $num  ',
                style: texto.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              Text(
                _formatarMoeda(_ultimoTrocoValor),
                style: texto.titleLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.1,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Text(titulo);
  }

  Widget _buildBotoesGestaoCaixa() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: _caixaAberto ? null : _abrirCaixa,
          icon: const Icon(Icons.lock_open_outlined),
          label: Text(
            _caixaAberto && _caixaAderidoRemoto
                ? 'Ja aberto na loja'
                : 'Abrir caixa',
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _caixaAberto && !_movimentoCaixaEmAndamento
              ? () => _registrarMovimentoCaixa(suprimento: true)
              : null,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Suprimento'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _caixaAberto && !_movimentoCaixaEmAndamento
              ? () => _registrarMovimentoCaixa(suprimento: false)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
          label: const Text('Sangria'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _caixaAberto ? _fecharCaixa : null,
          icon: const Icon(Icons.task_alt_outlined),
          label: const Text('Fechamento'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.podeLeituraParcialCaixa && _caixaAberto
              ? _mostrarLeituraParcial
              : null,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('Leitura parcial'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.podeVisualizarAuditoriaCaixa
              ? _abrirHistoricoAuditoria
              : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Auditoria'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _testarGavetaManual,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: const Text('Testar gaveta'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildGestaoCaixaColapsavel(BuildContext context) {
    final theme = Theme.of(context);
    final status = _caixaAberto
        ? (_caixaAderidoRemoto ? 'Aberto (aderido)' : 'Aberto')
        : 'Fechado';
    final operador = _operadorCaixa.trim().isEmpty ? '-' : _operadorCaixa;
    final avisosRede = _buildAvisosCaixasRemotos(context);
    final aberturaFmt = _aberturaCaixaEm == null
        ? '-'
        : DateFormat('dd/MM/yyyy HH:mm').format(_aberturaCaixaEm!.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() => _gestaoCaixaExpandida = !_gestaoCaixaExpandida);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.point_of_sale_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gestao de Caixa — $status · $operador',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (avisosRede.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.cloud_sync_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Icon(
                    _gestaoCaixaExpandida
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_gestaoCaixaExpandida) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_caixaAberto ? 'Status: Aberto' : 'Status: Fechado'),
                  Text('Operador: $operador'),
                  Text('Abertura: $aberturaFmt'),
                  const SizedBox(height: 4),
                  Text('Fundo inicial: ${_formatarMoeda(_fundoTrocoAbertura)}'),
                  Text('Suprimentos: ${_formatarMoeda(_totalSuprimentos)}'),
                  Text('Sangrias: ${_formatarMoeda(_totalSangrias)}'),
                  if (_terminalId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Terminal: $_terminalId',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  ...avisosRede,
                  const SizedBox(height: 10),
                  _buildBotoesGestaoCaixa(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPainelStatusCaixa(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGestaoCaixaColapsavel(context),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ultimas vendas finalizadas',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Toque na venda para segunda via, NFC-e, cancelar ou DANFE.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<UltimasVendasFinalizadasOrdenacao>(
                        tooltip:
                            'Ordenar: ${_ordenacaoUltimasVendas.rotuloCurto}',
                        icon: Icon(
                          Icons.swap_vert,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        onSelected: (ordenacao) => unawaited(
                          _alterarOrdenacaoUltimasVendas(ordenacao),
                        ),
                        itemBuilder: (context) => [
                          for (final o
                              in UltimasVendasFinalizadasOrdenacao.values)
                            PopupMenuItem(
                              value: o,
                              height: 40,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    child: o == _ordenacaoUltimasVendas
                                        ? Icon(
                                            Icons.check,
                                            size: 18,
                                            color: theme.colorScheme.primary,
                                          )
                                        : null,
                                  ),
                                  Expanded(child: Text(o.rotuloMenu)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _buildListaUltimasVendasFinalizadasCaixa(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListaUltimasVendasFinalizadasCaixa(BuildContext context) {
    return CaixaUltimasVendasList(
      vendas: _ultimasVendasFinalizadasParaCaixa(),
      clienteDaVenda: _clienteDaVenda,
      formatarMoeda: _formatarMoeda,
      onVendaTap: _abrirAcoesVendaFinalizada,
      ordenacao: _ordenacaoUltimasVendas,
      quantidadeItens: (v) {
        try {
          final repo = widget.vendaRepository;
          if (repo is VendaApiRepository) {
            return repo.itensDaVendaSafe(v).length;
          }
          return (repo.listarItensPorVenda(v.id) as List).length;
        } catch (_) {
          try {
            return v.itens.length;
          } catch (_) {
            return 0;
          }
        }
      },
    );
  }

  /// Conferencia cega: operador declara sem ver o esperado na digitacao.
  Widget _buildLinhaConferenciaFechamento({
    required String label,
    required TextEditingController controller,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        SizedBox(
          width: 170,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Declarado',
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPainelPagamentosMistoNoCaixa(
    BuildContext context, {
    required Venda venda,
    required double totalComDesconto,
  }) {
    if (_mistoValorControllers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final fiadoOrc = _valorFiadoMistoOrcamentoCaixa();
    final recebidoAgora = _somaMistoRecebidaNoCaixaAgora();
    final aPagarAgora =
        (totalComDesconto - fiadoOrc).clamp(0, double.infinity).toDouble();
    final pagamentoInsuficiente =
        recebidoAgora < aPagarAgora - _tolMistoPagamento;
    final trocoSobreTotal =
        (recebidoAgora - aPagarAgora).clamp(0.0, double.infinity).toDouble();
    final planoFiado = PlanoFiadoCodec.decode(venda.planoFiadoJson);
    final indicesCaixa = <int>[
      for (var i = 0; i < _mistoValorControllers.length; i++)
        if (_mistoLinhasModelo[i].meio != 'fiado') i,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pagamento misto',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _prepararEdicaoMisto(venda);
                    _sincronizarRecebidoPdVComOrcamento();
                  });
                  _focarEntradaPrincipalCaixa();
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Restaurar PDV'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChipResumoMisto(
                context,
                'A receber agora',
                _formatarMoeda(aPagarAgora),
              ),
              _buildChipResumoMisto(
                context,
                'Recebido no caixa',
                _formatarMoeda(recebidoAgora),
                corValor: pagamentoInsuficiente
                    ? theme.colorScheme.error
                    : null,
              ),
              if (fiadoOrc > 0.001)
                _buildChipResumoMisto(
                  context,
                  'Fiado (depois)',
                  _formatarMoeda(fiadoOrc),
                ),
              if (!pagamentoInsuficiente && trocoSobreTotal > 0.02)
                _buildChipResumoMisto(
                  context,
                  'Troco',
                  _formatarMoeda(trocoSobreTotal),
                  corValor: theme.colorScheme.primary,
                ),
            ],
          ),
          if (fiadoOrc > 0.001) ...[
            const SizedBox(height: 10),
            Text(
              PlanoFiadoCodec.formatarResumoLinhas(planoFiado).isEmpty
                  ? 'Fiado definido no PDV — nao entra no caixa agora.'
                  : PlanoFiadoCodec.formatarResumoLinhas(planoFiado),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (indicesCaixa.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var j = 0; j < indicesCaixa.length; j++) ...[
              if (j > 0) const SizedBox(height: 8),
              _buildLinhaValorMistoCaixa(context, index: indicesCaixa[j]),
            ],
          ],
          if (pagamentoInsuficiente)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Recebido agora menor que ${_formatarMoeda(aPagarAgora)} '
                '(total menos fiado).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipResumoMisto(
    BuildContext context,
    String rotulo,
    String valor, {
    Color? corValor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            valor,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: corValor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaValorMistoCaixa(BuildContext context, {required int index}) {
    final theme = Theme.of(context);
    final meio = _mistoLinhasModelo[index].meio;
    final parcelas = _mistoLinhasModelo[index].parcelas;
    final rotulo = '${_rotuloFormaPagamento(meio)}'
        '${meio == 'cartao_credito' ? ' · ${parcelas}x' : ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            rotulo,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _mistoValorControllers[index],
            focusNode: index < _mistoValorFocusNodes.length
                ? _mistoValorFocusNodes[index]
                : null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Valor no caixa',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() => _sincronizarRecebidoPdVComOrcamento());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumoCard(
    BuildContext context, {
    required String label,
    required String valor,
    bool destaque = false,
  }) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final color = destaque
        ? semantic?.successBg ?? Colors.green.shade50
        : semantic?.infoBg ?? Colors.blueGrey.shade50;
    final border = destaque
        ? semantic?.successBorder ?? Colors.green.shade200
        : semantic?.infoBorder ?? Colors.blueGrey.shade100;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            valor,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Resumo de troco apos cobranca — foco no botao Concluir venda.
class _DialogoResumoFechamentoVenda extends StatefulWidget {
  const _DialogoResumoFechamentoVenda({
    required this.numeroOrcamento,
    required this.textoPagamento,
    required this.textoPlanoFiado,
    required this.totalVenda,
    required this.descontoAplicado,
    required this.totalRecebido,
    required this.troco,
    required this.quantidadeItens,
    required this.formatarMoeda,
    required this.buildResumoCard,
  });

  final int numeroOrcamento;
  final String textoPagamento;
  final String? textoPlanoFiado;
  final double totalVenda;
  final double descontoAplicado;
  final double totalRecebido;
  final double troco;
  final int quantidadeItens;
  final String Function(double valor) formatarMoeda;
  final Widget Function(BuildContext context, {required String label, required String valor})
      buildResumoCard;

  @override
  State<_DialogoResumoFechamentoVenda> createState() =>
      _DialogoResumoFechamentoVendaState();
}

class _DialogoResumoFechamentoVendaState
    extends State<_DialogoResumoFechamentoVenda> {
  final _focusConcluir = FocusNode(debugLabel: 'caixaConcluirVenda');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusConcluir.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusConcluir.dispose();
    super.dispose();
  }

  void _concluir() {
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _concluir,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _concluir,
      },
      child: AlertDialog(
        title: Text('Venda ${widget.numeroOrcamento} finalizada'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pagamento: ${widget.textoPagamento}'),
              if (widget.textoPlanoFiado != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Plano fiado (definido no PDV):',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(widget.textoPlanoFiado!),
              ],
              const SizedBox(height: 4),
              Text('Itens: ${widget.quantidadeItens}'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: semantic?.successBg ?? Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: semantic?.successBorder ?? Colors.green.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('TROCO'),
                    const SizedBox(height: 4),
                    Text(
                      widget.formatarMoeda(widget.troco),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                                semantic?.successFg ?? Colors.green.shade800,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.descontoAplicado > 0) ...[
                    Expanded(
                      child: widget.buildResumoCard(
                        context,
                        label: 'DESCONTO',
                        valor: '- ${widget.formatarMoeda(widget.descontoAplicado)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: widget.buildResumoCard(
                      context,
                      label: 'TOTAL DA VENDA',
                      valor: widget.formatarMoeda(widget.totalVenda),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: widget.buildResumoCard(
                      context,
                      label: 'TOTAL RECEBIDO',
                      valor: widget.formatarMoeda(widget.totalRecebido),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar e nao finalizar'),
          ),
          Focus(
            focusNode: _focusConcluir,
            child: FilledButton(
              onPressed: _concluir,
              child: const Text('Concluir venda (Enter)'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialogo de pesquisa com ciclo de vida proprio (evita dispose antecipado do campo).
class _DialogoPesquisaOrcamento extends StatefulWidget {
  const _DialogoPesquisaOrcamento({
    required this.orcamentos,
    required this.clienteDaVenda,
    required this.rotuloVendedor,
    required this.formatarMoeda,
    required this.qtdItens,
    this.buscarPorNumero,
    this.buscarPorNumeroRemoto,
    this.recarregarLista,
  });

  final List<Venda> orcamentos;
  final Cliente? Function(Venda venda) clienteDaVenda;
  final String Function(Venda venda) rotuloVendedor;
  final String Function(double valor) formatarMoeda;
  final int Function(Venda venda) qtdItens;
  final Venda? Function(int numero)? buscarPorNumero;
  final Future<Venda?> Function(int numero)? buscarPorNumeroRemoto;
  final List<Venda> Function()? recarregarLista;

  @override
  State<_DialogoPesquisaOrcamento> createState() =>
      _DialogoPesquisaOrcamentoState();
}

class _DialogoPesquisaOrcamentoState extends State<_DialogoPesquisaOrcamento> {
  late final TextEditingController _pesquisaController;
  late final FocusNode _pesquisaFocusNode;
  late final ScrollController _listaScrollController;
  late List<Venda> _base;
  late List<Venda> _resultados;
  final ValueNotifier<int> _indiceSelecionado = ValueNotifier(0);
  Timer? _debounceSyncDialog;
  Timer? _debounceBuscaRemota;
  bool _buscandoRemoto = false;
  bool _fechando = false;

  @override
  void initState() {
    super.initState();
    _pesquisaController = TextEditingController();
    _pesquisaFocusNode = FocusNode();
    _listaScrollController = ScrollController();
    _base = List<Venda>.from(widget.orcamentos);
    _resultados = List<Venda>.from(_base);
    _indiceSelecionado.value = _resultados.isEmpty ? -1 : 0;
    SyncRefreshHub.instance.addListener(_aoSyncRede);
  }

  void _aoSyncRede() {
    if (!mounted) return;
    _debounceSyncDialog?.cancel();
    _debounceSyncDialog = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      final nova = widget.recarregarLista?.call();
      if (nova == null) return;
      setState(() => _base = List<Venda>.from(nova));
      _filtrar(_pesquisaController.text);
    });
  }

  @override
  void dispose() {
    SyncRefreshHub.instance.removeListener(_aoSyncRede);
    _debounceSyncDialog?.cancel();
    _debounceBuscaRemota?.cancel();
    _indiceSelecionado.dispose();
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    _listaScrollController.dispose();
    super.dispose();
  }

  void _rolarParaIndiceSelecionado() {
    final indice = _indiceSelecionado.value;
    if (!_listaScrollController.hasClients || indice < 0) {
      return;
    }
    const alturaEstimadaLinha = 72.0;
    final posicaoDesejada = (indice * alturaEstimadaLinha).clamp(
      0.0,
      _listaScrollController.position.maxScrollExtent,
    );
    _listaScrollController.animateTo(
      posicaoDesejada,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _selecionarIndice(int indice) {
    if (_fechando) return;
    if (indice < 0 || indice >= _resultados.length) return;
    _fechando = true;
    Navigator.of(context, rootNavigator: true).pop(_resultados[indice]);
  }

  void _definirIndiceSelecionado(int indice) {
    if (_indiceSelecionado.value == indice) return;
    _indiceSelecionado.value = indice;
  }

  KeyEventResult _tratarTeclaLista(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _resultados.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final atual = _indiceSelecionado.value;
      final novo = atual < 0
          ? 0
          : math.min(atual + 1, _resultados.length - 1);
      _definirIndiceSelecionado(novo);
      _rolarParaIndiceSelecionado();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final atual = _indiceSelecionado.value;
      final novo = atual < 0 ? 0 : math.max(atual - 1, 0);
      _definirIndiceSelecionado(novo);
      _rolarParaIndiceSelecionado();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.f1) {
      final indice = _indiceSelecionado.value >= 0 ? _indiceSelecionado.value : 0;
      _selecionarIndice(indice);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_fechando) return KeyEventResult.handled;
      _fechando = true;
      Navigator.of(context, rootNavigator: true).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _filtrar(String value) {
    final termo = value.trim().toLowerCase();
    setState(() {
      if (termo.isEmpty) {
        _resultados = List<Venda>.from(_base);
      } else {
        final filtrados = _base.where((orc) {
          final cliente = widget.clienteDaVenda(orc)?.nomeRazao ?? '';
          final vendedor = widget.rotuloVendedor(orc);
          return orc.numeroOrcamento.toString().contains(termo) ||
              cliente.toLowerCase().contains(termo) ||
              vendedor.toLowerCase().contains(termo);
        }).toList();

        final numero = int.tryParse(termo);
        if (numero != null && numero > 0) {
          final direto = widget.buscarPorNumero?.call(numero);
          if (direto != null &&
              !filtrados.any((o) => o.id == direto.id)) {
            filtrados.add(direto);
          }
        }
        filtrados.sort((a, b) {
          final na = a.numeroOrcamento > 0 ? a.numeroOrcamento : a.id;
          final nb = b.numeroOrcamento > 0 ? b.numeroOrcamento : b.id;
          return nb.compareTo(na);
        });
        _resultados = filtrados;
      }
      _indiceSelecionado.value = _resultados.isEmpty ? -1 : 0;
    });

    // Terminal: se digitou numero e nao achou no cache, busca na API.
    _debounceBuscaRemota?.cancel();
    final numeroRemoto = int.tryParse(termo);
    if (widget.buscarPorNumeroRemoto != null &&
        numeroRemoto != null &&
        numeroRemoto > 0 &&
        !_resultados.any((o) => o.numeroOrcamento == numeroRemoto)) {
      _debounceBuscaRemota = Timer(const Duration(milliseconds: 280), () {
        unawaited(_buscarRemotoPorNumero(numeroRemoto));
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listaScrollController.hasClients) {
        _listaScrollController.jumpTo(0);
      }
      if (_pesquisaFocusNode.canRequestFocus) {
        _pesquisaFocusNode.requestFocus();
      }
    });
  }

  Future<void> _buscarRemotoPorNumero(int numero) async {
    final fn = widget.buscarPorNumeroRemoto;
    if (fn == null || !mounted) return;
    setState(() => _buscandoRemoto = true);
    try {
      final v = await fn(numero);
      if (!mounted || v == null) return;
      setState(() {
        if (!_base.any((o) => o.id == v.id)) {
          _base = [v, ..._base];
        }
        if (!_resultados.any((o) => o.id == v.id)) {
          _resultados = [v, ..._resultados];
        }
        _indiceSelecionado.value = 0;
      });
    } catch (_) {
      // Mantem lista local; usuario ve "nenhum" se vazio.
    } finally {
      if (mounted) setState(() => _buscandoRemoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alturaDialogo =
        (MediaQuery.sizeOf(context).height * 0.62).clamp(320.0, 560.0);
    final corDestaque = Theme.of(context).colorScheme.primary.withValues(
          alpha: 0.08,
        );

    return Focus(
      onKeyEvent: _tratarTeclaLista,
      child: AlertDialog(
        title: const Text('Pesquisar orcamento'),
        content: SizedBox(
          width: 760,
          height: alturaDialogo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pesquisaController,
                focusNode: _pesquisaFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Numero, cliente, vendedor...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscandoRemoto
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _filtrar,
                onSubmitted: (_) {
                  if (_resultados.isEmpty) return;
                  final indice =
                      _indiceSelecionado.value >= 0 ? _indiceSelecionado.value : 0;
                  _selecionarIndice(indice);
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _resultados.isEmpty
                    ? Center(
                        child: Text(
                          _base.isEmpty
                              ? 'Nenhum orcamento pendente no servidor.'
                              : 'Nenhum orcamento encontrado para esta busca.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _listaScrollController,
                        itemCount: _resultados.length,
                        itemExtent: 72,
                        cacheExtent: 280,
                        itemBuilder: (context, index) {
                          final orc = _resultados[index];
                          String cliente;
                          try {
                            cliente =
                                widget.clienteDaVenda(orc)?.nomeRazao ??
                                'Sem cliente';
                          } catch (_) {
                            cliente = 'Sem cliente';
                          }
                          double descPdv = 0;
                          try {
                            descPdv = orc.descontoImplicitoTotal;
                          } catch (_) {}
                          final qtd = widget.qtdItens(orc);
                          return _OrcamentoPesquisaLinha(
                            indice: index,
                            indiceSelecionado: _indiceSelecionado,
                            corDestaque: corDestaque,
                            titulo: 'Orcamento ${orc.numeroOrcamento}',
                            subtitulo:
                                '$cliente | Itens: $qtd | Total: ${widget.formatarMoeda(orc.total)}'
                                '${descPdv > 0.001 ? ' | Desc. PDV: -${widget.formatarMoeda(descPdv)}' : ''}',
                            onHover: () => _definirIndiceSelecionado(index),
                            onTap: () => _selecionarIndice(index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_fechando) return;
              _fechando = true;
              Navigator.of(context, rootNavigator: true).pop();
            },
            child: const Text('Fechar (Esc)'),
          ),
        ],
      ),
    );
  }
}

/// Linha que so rebuilda quando entra/sai da selecao (ValueNotifier).
class _OrcamentoPesquisaLinha extends StatefulWidget {
  const _OrcamentoPesquisaLinha({
    required this.indice,
    required this.indiceSelecionado,
    required this.corDestaque,
    required this.titulo,
    required this.subtitulo,
    required this.onHover,
    required this.onTap,
  });

  final int indice;
  final ValueNotifier<int> indiceSelecionado;
  final Color corDestaque;
  final String titulo;
  final String subtitulo;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_OrcamentoPesquisaLinha> createState() => _OrcamentoPesquisaLinhaState();
}

class _OrcamentoPesquisaLinhaState extends State<_OrcamentoPesquisaLinha> {
  late bool _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.indiceSelecionado.value == widget.indice;
    widget.indiceSelecionado.addListener(_aoMudarSelecao);
  }

  @override
  void didUpdateWidget(covariant _OrcamentoPesquisaLinha oldWidget) {
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
    return MouseRegion(
      onEnter: (_) => widget.onHover(),
      child: ListTile(
        selected: _selecionado,
        selectedTileColor: widget.corDestaque,
        title: Text(widget.titulo),
        subtitle: Text(widget.subtitulo),
        onTap: widget.onTap,
      ),
    );
  }
}

class _ImportarOrcamentoIntent extends Intent {
  const _ImportarOrcamentoIntent();
}

class _SegundaViaCupomIntent extends Intent {
  const _SegundaViaCupomIntent();
}

class _ReceberFiadoIntent extends Intent {
  const _ReceberFiadoIntent();
}

class _VincularClienteIntent extends Intent {
  const _VincularClienteIntent();
}

class _BuscarProdutoConferenciaIntent extends Intent {
  const _BuscarProdutoConferenciaIntent();
}

class _ResultadoMovimentoCaixa {
  const _ResultadoMovimentoCaixa({
    required this.valor,
    required this.observacao,
    required this.sessao,
  });

  final double valor;
  final String observacao;
  final CaixaSessao sessao;
}

class _DialogoSangriaSuprimento extends StatefulWidget {
  const _DialogoSangriaSuprimento({
    required this.suprimento,
    required this.parseValor,
    required this.registrar,
  });

  final bool suprimento;
  final double? Function(String texto) parseValor;
  final Future<CaixaSessao> Function(double valor) registrar;

  @override
  State<_DialogoSangriaSuprimento> createState() =>
      _DialogoSangriaSuprimentoState();
}

class _DialogoSangriaSuprimentoState extends State<_DialogoSangriaSuprimento> {
  final _valorController = TextEditingController();
  final _obsController = TextEditingController();
  bool _salvando = false;
  String _erro = '';

  @override
  void dispose() {
    _valorController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_salvando) return;
    final valor = widget.parseValor(_valorController.text) ?? 0;
    if (valor <= 0) {
      setState(() => _erro = 'Informe um valor valido.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = '';
    });
    try {
      final sessao = await widget.registrar(valor);
      if (!mounted) return;
      Navigator.pop(
        context,
        _ResultadoMovimentoCaixa(
          valor: valor,
          observacao: _obsController.text.trim(),
          sessao: sessao,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro =
            'Nao foi possivel registrar a movimentacao: ${LanApiFeedback.mensagem(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_salvando,
      child: AlertDialog(
        title: Text(
          widget.suprimento ? 'Registrar suprimento' : 'Registrar sangria',
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _valorController,
                  enabled: !_salvando,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    hintText: 'Ex.: 100,00',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _obsController,
                  enabled: !_salvando,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observacao (opcional)',
                  ),
                ),
                if (_erro.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _erro,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _salvando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _salvando ? null : _confirmar,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(96, 40),
            ),
            child: _salvando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

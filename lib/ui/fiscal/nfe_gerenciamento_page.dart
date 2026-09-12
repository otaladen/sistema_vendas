// Painel fiscal NF-e modelo 55 — sem alteracao de estoque (apenas faturamento).

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/sync/sync_cursor_storage.dart';
import '../../services/focus_nfe_reconsulta_helper.dart';
import '../../config/focus_nfe_runtime.dart';
import '../../data/api/cliente_api_repository.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/produto_api_repository.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/app_config_repository.dart' show EmpresaConfig;
import '../../services/configuracoes_service.dart';
import '../../data/nfe_inutilizacao_store.dart';
import '../../data/nfe_saida_fiscal_store.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../config/fiscal_config.dart';
import '../../domain/fiscal/endereco_fiscal_ibge_resolver.dart';
import '../../domain/auditoria_catalogo.dart';
import '../../domain/entregas/romaneio_carga_merge.dart';
import '../../domain/fiscal/nfe_carta_correcao_registro.dart';
import '../../domain/fiscal/nfe_cce_reconciliacao.dart';
import '../../domain/fiscal/nfe_cce_xml_local_service.dart';
import '../../domain/fiscal/nfe_historico_csv_export.dart';
import '../../domain/fiscal/nfe_historico_filtro.dart';
import '../../domain/fiscal/nfe_painel_resumo.dart';
import '../../domain/fiscal/nfe_pendencias_filtro.dart';
import '../../domain/fiscal/nfe_pendencias_service.dart';
import '../../domain/fiscal/nfe_xml_local_service.dart';
import '../../domain/fiscal/nfe_pre_emissao_service.dart';
import '../../domain/fiscal/nfe_referencia_resolver.dart';
import '../../domain/fiscal/nfe_registro_focus_merge.dart';
import '../../domain/fiscal/nfe_venda_sync.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../domain/fiscal/nfe_whatsapp_helper.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../model/usuario_sistema.dart';
import '../../services/auditoria_registrar.dart';
import '../../domain/fiscal/nfe_logistica_sugerida.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../model/cliente.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../../services/focus_nfe_service.dart';
import '../shell/main_menu_deps.dart';
import '../widgets/lan_api_feedback.dart';
import 'exportar_fechamento_page.dart';
import 'nfe_autorizacao.dart';
import 'nfe_enviar_email_dialog.dart';
import 'nfe_inutilizacao_dialog.dart';
import 'nfe_inutilizacao_historico_dialog.dart';
import 'relatorio_fiscal_mensal_page.dart';
import 'widgets/fiscal_rejeicao_detalhe_dialog.dart';
import 'widgets/nfe_aba_pendencias.dart';
import 'widgets/nfe_ambiente_banner.dart';
import 'widgets/nfe_checklist_panel.dart';
import 'widgets/nfe_cobranca_resumo_panel.dart';
import 'widgets/nfe_historico_acoes_dialog.dart';
import 'widgets/nfe_historico_card.dart';
import 'widgets/nfe_historico_filtros_bar.dart';
import 'widgets/nfe_itens_fiscais_table.dart';
import 'widgets/nfe_painel_resumo_bar.dart';
import 'widgets/nfe_previa_emissao_dialog.dart';
import 'widgets/nfe_registro_detalhe_dialog.dart';

/// Emissao e historico de NF-e de saida (Focus NFe) para vendas finalizadas.
class NfeGerenciamentoPage extends StatefulWidget {
  const NfeGerenciamentoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.configuracoesService,
    required this.usuarioLogado,
    this.vendaIdInicial,
    this.abaInicial = 0,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final ConfiguracoesService configuracoesService;
  final UsuarioSistema usuarioLogado;
  final int? vendaIdInicial;
  final int abaInicial;

  @override
  State<NfeGerenciamentoPage> createState() => _NfeGerenciamentoPageState();
}

class _NfeGerenciamentoPageState extends State<NfeGerenciamentoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late FocusNfeService _focusNfe;
  NfeSaidaFiscalStore? _historicoStore;
  NfeInutilizacaoStore? _inutilizacaoStore;
  late final dynamic _usuarioRepository;
  Timer? _timerReconsultaPendencias;
  Timer? _wsDebounce;
  VoidCallback? _syncHubListener;
  bool? _apiOnlineAnterior;
  final _currency = NumberFormat('#,##0.00', 'pt_BR');
  final _buscaVendaController = TextEditingController();
  final _historicoBuscaController = TextEditingController();
  NfeHistoricoFiltro _filtroHistorico = const NfeHistoricoFiltro();
  NfePendenciasFiltro _filtroPendencias = const NfePendenciasFiltro();

  List<Venda> _vendasElegiveis = [];
  List<NfeSaidaFiscalRegistro> _historico = [];
  List<NfePendenciaVenda> _pendenciasVendas = [];
  List<NfeSaidaFiscalRegistro> _pendenciasProcessando = [];
  List<NfeSaidaFiscalRegistro> _pendenciasRejeitadas = [];
  NfePainelResumo _resumo = const NfePainelResumo(
    totalRegistros: 0,
    autorizadas: 0,
    processando: 0,
    rejeitadas: 0,
    canceladas: 0,
    vendasSemNfeAutorizada: 0,
    totalCartasCorrecao: 0,
    cartasCorrecaoProcessando: 0,
    lacunasNumeracaoSerie1: 0,
    inutilizacoesRegistradas: 0,
  );
  int get _contagemPendenciasOperacionais =>
      _resumo.vendasSemNfeAutorizada +
      _resumo.processando +
      _resumo.rejeitadas;

  Venda? _vendaSelecionada;
  Cliente? _cliente;
  EnderecoIbgeResolvido? _ibgeResolvido;
  EmpresaConfig? _empresa;

  bool _carregandoVendas = true;
  bool _carregandoDados = false;
  bool _emitindo = false;
  String _statusIbge = '';
  NfePreEmissaoResultado? _preEmissao;
  final Map<int, bool> _vendaComNfeAutorizada = {};
  String? _deviceIdSync;

  int _modalidadeFrete = 9;
  String _logisticaDica = '';
  final _placaController = TextEditingController();
  final _volumesController = TextEditingController(text: '1');
  final _pesoController = TextEditingController();

  bool get _viaApi => widget.vendaRepository is VendaApiRepository;

  @override
  void initState() {
    super.initState();
    final idInicial = widget.vendaIdInicial;
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.abaInicial.clamp(0, 2),
    );
    if (!_viaApi && widget.vendaRepository is VendaRepository) {
      final path =
          (widget.vendaRepository as VendaRepository).objectBox.storeDirectoryPath;
      _historicoStore = NfeSaidaFiscalStore(path);
      _inutilizacaoStore = NfeInutilizacaoStore(path);
    }
    _focusNfe = FocusNfeService(config: criarFocusNfeConfigPadrao());
    unawaited(_recarregarConfigFocus());
    _usuarioRepository =
        MainMenuDeps.resolverUsuarioRepository(context);
    _tabs.addListener(_onTabIndexChanged);
    if (_viaApi) {
      _apiOnlineAnterior = LanApiEventHub.instance.online;
      LanApiEventHub.instance.addListener(_onLanApiEvento);
    } else {
      _syncHubListener = () {
        if (!mounted) return;
        unawaited(_recarregarHistorico());
        unawaited(_carregarVendas());
      };
      SyncRefreshHub.instance.addListener(_syncHubListener!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recarregarHistorico());
      unawaited(_carregarVendas());
    });
    _carregarEmpresa();
    unawaited(_carregarDeviceIdSync());
    if (idInicial != null && idInicial > 0) {
      _buscaVendaController.text = '$idInicial';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_inicializarComVendaInicial(idInicial));
      });
    }
  }

  void _onLanApiEvento() {
    if (!_viaApi) return;
    final hub = LanApiEventHub.instance;
    final online = hub.online;
    final ficouOnline = online && _apiOnlineAnterior == false;
    _apiOnlineAnterior = online;
    if (hub.deveBloquearOperacoes) return;
    final ent = hub.ultimaEntidade;
    if (!ficouOnline &&
        ent != 'venda' &&
        ent != 'nfe_saida' &&
        ent != 'fiscal' &&
        ent != 'produto' &&
        ent != 'cliente') {
      return;
    }
    _wsDebounce?.cancel();
    _wsDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_recarregarHistorico());
      unawaited(_carregarVendas());
    });
  }

  /// Abertura pelo caixa: aba Emitir, busca da venda e resolucao IBGE automaticas.
  Future<void> _inicializarComVendaInicial(int vendaId) async {
    if (!mounted) return;
    if (_tabs.index != 0) {
      _tabs.animateTo(0);
    }
    await _buscarVendaPorNumero();
  }

  @override
  void dispose() {
    _wsDebounce?.cancel();
    LanApiEventHub.instance.removeListener(_onLanApiEvento);
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    _pararTimerReconsulta();
    _tabs.removeListener(_onTabIndexChanged);
    _tabs.dispose();
    _buscaVendaController.dispose();
    _historicoBuscaController.dispose();
    _placaController.dispose();
    _volumesController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDeviceIdSync() async {
    _deviceIdSync = await SyncCursorStorage().obterOuCriarDeviceId();
  }

  Future<void> _carregarEmpresa() async {
    final cfg = await widget.configuracoesService.carregarEfetiva();
    if (!mounted) return;
    setState(() => _empresa = cfg);
  }

  void _onTabIndexChanged() {
    if (_tabs.index == 1 && _pendenciasProcessando.isNotEmpty) {
      _iniciarTimerReconsulta();
    } else {
      _pararTimerReconsulta();
    }
  }

  void _iniciarTimerReconsulta() {
    _pararTimerReconsulta();
    _timerReconsultaPendencias = Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (!_emitindo && _pendenciasProcessando.isNotEmpty && mounted) {
          unawaited(_reconsultarTodasProcessando());
        }
      },
    );
  }

  void _pararTimerReconsulta() {
    _timerReconsultaPendencias?.cancel();
    _timerReconsultaPendencias = null;
  }

  Future<void> _recarregarConfigFocus() async {
    await widget.configuracoesService.carregarFiscalGlobal();
    if (!mounted) return;
    setState(() {
      _focusNfe = FocusNfeService(config: criarFocusNfeConfigPadrao());
    });
    _atualizarPreEmissao();
  }

  void _persistirRegistro(NfeSaidaFiscalRegistro registro) {
    if (_viaApi) {
      // Persistencia ocorre no PC servidor via API.
      return;
    }
    _historicoStore?.gravar(registro);
    if (widget.vendaRepository is VendaRepository) {
      NfeVendaSync.aplicarRegistroNoRepositorio(
        vendaRepository: widget.vendaRepository as VendaRepository,
        registro: registro,
      );
    }
    unawaited(_arquivarXmlLocal(registro));
  }

  Future<void> _arquivarXmlLocal(NfeSaidaFiscalRegistro registro) async {
    if (_viaApi || widget.vendaRepository is! VendaRepository) return;
    final chave = registro.chaveNfe.trim();
    final storePath =
        (widget.vendaRepository as VendaRepository).objectBox.storeDirectoryPath;
    if (registro.urlXml.trim().isNotEmpty) {
      await NfeXmlLocalService.arquivarOuEnfileirar(
        storeDirectoryPath: storePath,
        chaveAcesso: chave,
        urlXml: registro.urlXml,
      );
    }
    if (registro.urlXmlEventoCancelamento.trim().isNotEmpty) {
      await NfeXmlLocalService.arquivarOuEnfileirar(
        storeDirectoryPath: storePath,
        chaveAcesso: chave,
        urlXml: registro.urlXmlEventoCancelamento,
        cancelada: true,
      );
    }
  }

  List<NfeSaidaFiscalRegistro> _historicoDaVenda(int vendaId) {
    return _historico.where((r) => r.vendaId == vendaId).toList();
  }

  Future<bool> _garantirPermissaoCancelarNfe() async {
    if (usuarioPodeCancelarNfeSaida(widget.usuarioLogado)) return true;
    return solicitarAutorizacaoNfeFiscal(
      context,
      _usuarioRepository,
      titulo: 'Autorizar acao fiscal',
      mensagem:
          'Cancelamento ou carta de correcao exige permissao de gerente.',
    );
  }

  Future<void> _recarregarHistorico() async {
    if (_viaApi) {
      if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
        return;
      }
      final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
      if (client == null) {
        if (mounted) {
          setState(() {
            _historico = [];
            _pendenciasVendas = [];
            _pendenciasProcessando = [];
            _pendenciasRejeitadas = [];
          });
        }
        return;
      }
      try {
        final painel = await client.listarNfeSaidaPainel();
        final raw = painel['items'];
        final lista = raw is List
            ? raw
                .whereType<Map>()
                .map(
                  (e) => NfeSaidaFiscalRegistro.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false)
            : <NfeSaidaFiscalRegistro>[];
        final mapa = <int, bool>{};
        for (final r in lista) {
          if (r.vendaId > 0 && r.autorizada) mapa[r.vendaId] = true;
        }

        final pend = painel['pendencias'];
        List<NfePendenciaVenda> vendasSem = const [];
        List<NfeSaidaFiscalRegistro> processando = const [];
        List<NfeSaidaFiscalRegistro> rejeitadas = const [];
        if (pend is Map) {
          final vs = pend['vendasSemNfe'];
          if (vs is List) {
            vendasSem = [
              for (final e in vs)
                if (e is Map)
                  NfePendenciaVenda(
                    venda: LanApiClient.vendaCompletaDeMap(
                      Map<String, dynamic>.from(
                        e['venda'] is Map
                            ? Map<String, dynamic>.from(e['venda'] as Map)
                            : e,
                      ),
                    ),
                    clienteNome: (e['clienteNome'] ?? 'Sem cliente').toString(),
                    ultimoStatusNfe: (e['ultimoStatusNfe'] ?? '').toString(),
                  ),
            ];
          }
          final pr = pend['processando'];
          if (pr is List) {
            processando = pr
                .whereType<Map>()
                .map(
                  (e) => NfeSaidaFiscalRegistro.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList();
          }
          final rj = pend['rejeitadas'];
          if (rj is List) {
            rejeitadas = rj
                .whereType<Map>()
                .map(
                  (e) => NfeSaidaFiscalRegistro.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList();
          }
        } else {
          processando = lista.where((r) => r.processando).toList();
          rejeitadas = lista.where((r) => r.rejeitada).toList();
        }

        final meta = painel['meta'];
        final NfePainelResumo resumo;
        if (meta is Map) {
          resumo = NfePainelResumo(
            totalRegistros: (meta['totalRegistros'] as num?)?.toInt() ??
                lista.length,
            autorizadas: (meta['autorizadas'] as num?)?.toInt() ??
                lista.where((r) => r.autorizada).length,
            processando: (meta['processando'] as num?)?.toInt() ??
                processando.length,
            rejeitadas:
                (meta['rejeitadas'] as num?)?.toInt() ?? rejeitadas.length,
            canceladas: (meta['canceladas'] as num?)?.toInt() ??
                lista.where((r) => r.cancelada).length,
            vendasSemNfeAutorizada:
                (meta['vendasSemNfeAutorizada'] as num?)?.toInt() ??
                    vendasSem.length,
            totalCartasCorrecao:
                (meta['totalCartasCorrecao'] as num?)?.toInt() ?? 0,
            cartasCorrecaoProcessando:
                (meta['cartasCorrecaoProcessando'] as num?)?.toInt() ?? 0,
            lacunasNumeracaoSerie1:
                (meta['lacunasNumeracaoSerie1'] as num?)?.toInt() ?? 0,
            inutilizacoesRegistradas:
                (meta['inutilizacoesRegistradas'] as num?)?.toInt() ?? 0,
          );
        } else {
          resumo = NfePainelResumo(
            totalRegistros: lista.length,
            autorizadas: lista.where((r) => r.autorizada).length,
            processando: processando.length,
            rejeitadas: rejeitadas.length,
            canceladas: lista.where((r) => r.cancelada).length,
            vendasSemNfeAutorizada: vendasSem.length,
            totalCartasCorrecao:
                lista.fold<int>(0, (a, r) => a + r.totalCartasCorrecao),
            cartasCorrecaoProcessando:
                lista.fold<int>(0, (a, r) => a + r.cartasCorrecaoProcessando),
            lacunasNumeracaoSerie1: 0,
            inutilizacoesRegistradas: 0,
          );
        }

        if (!mounted) return;
        setState(() {
          _historico = lista;
          _vendaComNfeAutorizada
            ..clear()
            ..addAll(mapa);
          _pendenciasVendas = _filtroPendencias.aplicar(
            vendasSem,
            clienteRepository: widget.clienteRepository,
          );
          _pendenciasProcessando = processando;
          _pendenciasRejeitadas = rejeitadas;
          _resumo = resumo;
        });
        _atualizarPreEmissao();
      } catch (e) {
        if (mounted) {
          LanApiFeedback.snackErro(
            context,
            e,
            prefixo: 'Falha ao carregar historico NF-e',
          );
        }
      }
      return;
    }

    final store = _historicoStore;
    final inut = _inutilizacaoStore;
    if (store == null ||
        inut == null ||
        widget.vendaRepository is! VendaRepository) {
      return;
    }
    final vendaRepo = widget.vendaRepository as VendaRepository;
    final lista = NfeVendaSync.listarHistoricoUnificado(
      store: store,
      vendaRepository: vendaRepo,
    );
    final mapa = <int, bool>{};
    for (final r in lista) {
      if (r.vendaId > 0 && r.autorizada) {
        mapa[r.vendaId] = true;
      }
    }
    final semNfe = _filtroPendencias.aplicar(
      NfePendenciasService.listarVendasSemNfeAutorizada(
        vendaRepository: vendaRepo,
        nfeStore: store,
      ),
      clienteRepository: widget.clienteRepository,
    );
    final comAuth = NfePendenciasService.idsVendasComNfeAutorizada(
      store,
      vendaRepository: vendaRepo,
    );
    final resumo = NfePainelResumoBuilder.calcular(
      historico: lista,
      vendasSemNfe: semNfe.length,
      inutilizacaoStore: inut,
      nfeStore: store,
      vendasComNfeAutorizada: comAuth,
    );
    if (!mounted) return;
    setState(() {
      _historico = lista;
      _vendaComNfeAutorizada
        ..clear()
        ..addAll(mapa);
      _pendenciasVendas = semNfe;
      _pendenciasProcessando = NfePendenciasService.listarProcessando(
        store,
        vendaRepository: vendaRepo,
      );
      _pendenciasRejeitadas = NfePendenciasService.listarRejeitadasRecentes(
        store,
        vendaRepository: vendaRepo,
      );
      _resumo = resumo;
    });
    _atualizarPreEmissao();
  }

  void _registrarAuditoriaNfe({
    required String acao,
    required String resumo,
    String entidadeId = '',
    Map<String, dynamic>? detalhes,
  }) {
    if (_viaApi) return;
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.fiscal,
      acao: acao,
      entidade: 'nfe_saida',
      entidadeId: entidadeId,
      resumo: resumo,
      detalhes: detalhes,
    );
  }

  List<ItemVenda> _itensDaVenda(Venda venda) {
    if (widget.vendaRepository is VendaApiRepository) {
      return (widget.vendaRepository as VendaApiRepository)
          .itensDaVendaSafe(venda);
    }
    return RomaneioCargaMerge.itensDaVendaSafe(venda);
  }

  dynamic get _produtoRepository =>
      MainMenuDeps.maybeOf(context)?.produtoRepository;

  void _atualizarPreEmissao() {
    final venda = _vendaSelecionada;
    if (venda == null) {
      setState(() => _preEmissao = null);
      return;
    }
    NfeSaidaFiscalRegistro? nfeAuth;
    final rawAuth =
        widget.vendaRepository.obterNfe55AutorizadaPorVenda(venda.id);
    if (rawAuth is NfeSaidaFiscalRegistro) {
      nfeAuth = rawAuth;
    }
    nfeAuth ??= _historicoStore?.ultimaAutorizadaPorVenda(venda.id);
    nfeAuth ??= _historico.cast<NfeSaidaFiscalRegistro?>().firstWhere(
          (r) => r != null && r.vendaId == venda.id && r.autorizada,
          orElse: () => null,
        );
    final historicoVenda = _historicoDaVenda(venda.id);
    final nfeUltima = historicoVenda.isNotEmpty
        ? historicoVenda.first
        : _historicoStore?.ultimaPorVenda(venda.id);
    final itens = _itensDaVenda(venda);
    final prodRepo = _produtoRepository;
    setState(() {
      _preEmissao = NfePreEmissaoService.avaliar(
        venda: venda,
        cliente: _cliente,
        ibge: _ibgeResolvido,
        nfeAutorizada: nfeAuth,
        nfeUltima: nfeUltima,
        deviceIdAtual: _deviceIdSync,
        emissaoNoServidor: _viaApi,
        fiscal: widget.configuracoesService.fiscalEmCache,
        itens: itens,
        resolverProduto: prodRepo == null
            ? null
            : (id) {
                try {
                  return prodRepo.obterPorId(id);
                } catch (_) {
                  return null;
                }
              },
      );
    });
  }

  Future<void> _carregarVendas() async {
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      if (mounted) setState(() => _carregandoVendas = false);
      return;
    }
    setState(() => _carregandoVendas = true);
    try {
      if (_viaApi && widget.vendaRepository is VendaApiRepository) {
        await (widget.vendaRepository as VendaApiRepository)
            .hidratarVendasFinalizadas(limit: 120);
      }
      final lista = widget.vendaRepository.listarUltimasVendasFinalizadas(
        limit: 80,
      );
      if (!mounted) return;
      setState(() {
        _vendasElegiveis = List<Venda>.from(lista);
        _carregandoVendas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoVendas = false);
      if (_viaApi) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao carregar vendas');
      } else {
        _snack('Falha ao carregar vendas: $e', erro: true);
      }
    }
  }

  Future<void> _buscarVendaPorNumero() async {
    final n = int.tryParse(_buscaVendaController.text.trim());
    if (n == null || n <= 0) {
      _snack('Informe o numero do orcamento ou ID da venda.', erro: true);
      return;
    }
    var v = widget.vendaRepository.buscarVendaFinalizadaPorNumeroOuId(n);
    if (v == null &&
        _viaApi &&
        widget.vendaRepository is VendaApiRepository) {
      if (!LanApiEventHub.instance.garantirOnlineOuAvisar(context)) return;
      try {
        final atualizada = await (widget.vendaRepository as VendaApiRepository)
            .atualizarVendaFinalizadaNoCache(n);
        if (atualizada != null &&
            atualizada.status == 'finalizada' &&
            !atualizada.cancelada) {
          v = atualizada;
        } else {
          // Busca por numero de orcamento: hidrata lista e tenta de novo.
          await (widget.vendaRepository as VendaApiRepository)
              .hidratarVendasFinalizadas(limit: 200);
          v = widget.vendaRepository.buscarVendaFinalizadaPorNumeroOuId(n);
        }
      } catch (e) {
        if (mounted) {
          LanApiFeedback.snackErro(context, e, prefixo: 'Busca de venda');
        }
        return;
      }
    }
    if (v == null) {
      _snack('Venda finalizada nao encontrada.', erro: true);
      return;
    }
    await _selecionarVenda(v);
  }

  Future<void> _selecionarVenda(Venda venda) async {
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    Venda vendaCompleta = venda;
    if (_viaApi && widget.vendaRepository is VendaApiRepository) {
      try {
        final atualizada = await (widget.vendaRepository as VendaApiRepository)
            .atualizarVendaFinalizadaNoCache(venda.id);
        if (atualizada != null) vendaCompleta = atualizada;
      } catch (_) {
        vendaCompleta =
            widget.vendaRepository.obterPorId(venda.id) ?? venda;
      }
    } else {
      vendaCompleta = widget.vendaRepository.obterPorId(venda.id) ?? venda;
    }

    var cliente = VendaRelacaoSafe.cliente(
      vendaCompleta,
      clienteRepository: widget.clienteRepository,
    );
    if (cliente == null &&
        vendaCompleta.cliente.targetId > 0 &&
        widget.clienteRepository is ClienteApiRepository) {
      try {
        cliente = await (widget.clienteRepository as ClienteApiRepository)
            .obterPorIdRemoto(vendaCompleta.cliente.targetId);
      } catch (_) {}
    }

    await _garantirProdutosDosItens(vendaCompleta);

    if (!mounted) return;
    setState(() {
      _vendaSelecionada = vendaCompleta;
      _cliente = cliente;
      _ibgeResolvido = null;
      _preEmissao = null;
      _statusIbge = 'Resolvendo codigo IBGE...';
      _carregandoDados = true;
    });

    _aplicarLogisticaSugerida(vendaCompleta);

    if (_cliente == null) {
      setState(() {
        _carregandoDados = false;
        _statusIbge =
            'Venda sem cliente vinculado. Vincule um cadastro antes da NF-e.';
      });
      _atualizarPreEmissao();
      return;
    }

    final ibge = await EnderecoFiscalIbgeResolver.resolverParaCliente(_cliente!);
    if (!mounted) return;

    if (ibge.sucesso && ibge.endereco != null && ibge.origem == 'brasilapi_cep') {
      final atualizado = EnderecoFiscalIbgeResolver.aplicarIbgeNoCliente(
        _cliente!,
        ibge.endereco!,
      );
      if (widget.clienteRepository is ClienteApiRepository) {
        try {
          await (widget.clienteRepository as ClienteApiRepository)
              .salvarRemoto(atualizado);
          _cliente =
              widget.clienteRepository.obterPorId(_cliente!.id) ?? atualizado;
        } catch (_) {
          _cliente = atualizado;
        }
      } else {
        widget.clienteRepository.salvar(atualizado);
        _cliente =
            widget.clienteRepository.obterPorId(_cliente!.id) ?? atualizado;
      }
    }

    setState(() {
      _ibgeResolvido = ibge;
      _carregandoDados = false;
      _statusIbge = ibge.sucesso
          ? 'IBGE ${ibge.codigoIbge} (${ibge.origem}).'
          : ibge.mensagem;
    });
    _atualizarPreEmissao();
  }

  Future<void> _garantirProdutosDosItens(Venda venda) async {
    final prodRepo = _produtoRepository;
    if (prodRepo is! ProdutoApiRepository) return;
    final ids = <int>{};
    for (final item in _itensDaVenda(venda)) {
      final pid = item.produto.targetId;
      if (pid > 0 && prodRepo.obterPorId(pid) == null) ids.add(pid);
    }
    for (final id in ids) {
      try {
        await prodRepo.obterPorIdRemoto(id);
      } catch (_) {}
    }
  }

  void _aplicarLogisticaSugerida(Venda venda) {
    final sug = NfeLogisticaSugerida.calcular(
      venda,
      itens: _itensDaVenda(venda),
    );
    _modalidadeFrete = sug.modalidadeFrete;
    _volumesController.text = '${sug.volumes}';
    _pesoController.text = sug.pesoBrutoKg.toStringAsFixed(3);
    _placaController.text = sug.placaVeiculo;
    _logisticaDica = '${sug.rotuloModalidade} — ${sug.mensagem}';
  }

  FocusNfeDestinatarioNfe? _montarDestinatario() {
    if (_cliente == null || _ibgeResolvido == null || !_ibgeResolvido!.sucesso) {
      return null;
    }
    final end = _ibgeResolvido!.endereco;
    if (end == null) return null;
    return FocusNfeDestinatarioNfe.fromCliente(
      _cliente!,
      codigoMunicipioIbge: _ibgeResolvido!.codigoIbge,
      enderecoOverride: end,
    );
  }

  FocusNfeDadosLogistica _montarLogistica() {
    final volumes = int.tryParse(_volumesController.text) ?? 1;
    final peso = double.tryParse(_pesoController.text.replaceAll(',', '.')) ?? 0;
    return FocusNfeDadosLogistica(
      modalidadeFrete: _modalidadeFrete,
      placaVeiculo: _placaController.text.trim(),
      volumes: volumes > 0 ? volumes : 1,
      pesoBrutoKg: peso > 0 ? peso : volumes.toDouble(),
    );
  }

  /// Fase 2: previa (payload + DANFe) e confirmacao antes da SEFAZ.
  Future<void> _revisarEConfirmarEmissao() async {
    final venda = _vendaSelecionada;
    if (venda == null) {
      _snack('Selecione uma venda finalizada.', erro: true);
      return;
    }
    if (!usuarioPodeEmitirNfeSaida(widget.usuarioLogado)) {
      _snack('Sem permissao para emitir NF-e de saida.', erro: true);
      return;
    }
    if (_viaApi &&
        !LanApiEventHub.instance.garantirOnlineOuAvisar(context)) {
      return;
    }
    if (_preEmissao == null || !_preEmissao!.podeEmitir) {
      _snack(
        'Corrija as pendencias do checklist antes de emitir a NF-e.',
        erro: true,
      );
      return;
    }
    final dest = _montarDestinatario();
    if (dest == null) {
      _snack(
        _statusIbge.isEmpty ? 'Dados do destinatario incompletos.' : _statusIbge,
        erro: true,
      );
      return;
    }

    if (_viaApi) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Emitir NF-e no servidor'),
          content: Text(
            'A emissao sera executada no PC servidor (Focus/SEFAZ) para a '
            'venda #${venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id}.\n\n'
            'Destinatario: ${dest.nome}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Emitir'),
            ),
          ],
        ),
      );
      if (confirmou == true && mounted) {
        await _executarEmissaoNfeViaApi(venda, dest);
      }
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = _focusNfe.montarPayloadNfe(
        venda,
        destinatario: dest,
        logistica: _montarLogistica(),
      );
    } on FocusNfeValidacaoException catch (e) {
      _snack(e.message, erro: true);
      return;
    } on FocusNfeConfigIncompletaException catch (e) {
      _snack(e.message, erro: true);
      return;
    }

    final historicoVenda = _historicoDaVenda(venda.id);
    final referencia = NfeReferenciaResolver.proximaParaEmissao(
      venda: venda,
      ultimaLocal:
          historicoVenda.isNotEmpty ? historicoVenda.first : null,
      historicoVenda: historicoVenda,
    );
    final confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => NfePreviaEmissaoDialog(
        focusNfe: _focusNfe,
        payload: payload,
        venda: venda,
        preEmissao: _preEmissao!,
        referencia: referencia,
      ),
    );

    if (confirmou == true && mounted) {
      await _executarEmissaoNfe(venda, dest, referencia: referencia);
    }
  }

  Future<void> _executarEmissaoNfeViaApi(
    Venda venda,
    FocusNfeDestinatarioNfe dest,
  ) async {
    final client = MainMenuDeps.maybeOf(context)?.lanApiClient;
    if (client == null) {
      _snack('API do servidor indisponivel para emitir NF-e.', erro: true);
      return;
    }
    setState(() => _emitindo = true);
    final logistica = _montarLogistica();
    try {
      final r = await client.emitirNfe(
        venda.id,
        destinatario: {
          'nome': dest.nome,
          'documento': dest.documento,
          'inscricaoEstadual': dest.inscricaoEstadual,
          'indicadorInscricaoEstadual': dest.indicadorInscricaoEstadual,
          'logradouro': dest.logradouro,
          'numero': dest.numero,
          'bairro': dest.bairro,
          'municipio': dest.municipio,
          'codigoMunicipioIbge': dest.codigoMunicipioIbge,
          'uf': dest.uf,
          'cep': dest.cep,
          'telefone': dest.telefone,
          'email': dest.email,
          'complemento': dest.complemento,
        },
        logistica: {
          'modalidadeFrete': logistica.modalidadeFrete,
          'placaVeiculo': logistica.placaVeiculo,
          'volumes': logistica.volumes,
          'pesoBrutoKg': logistica.pesoBrutoKg,
          'especieVolumes': logistica.especieVolumes,
        },
      );
      if (!mounted) return;
      setState(() => _emitindo = false);
      if (r['ok'] == true) {
        await (widget.vendaRepository as VendaApiRepository)
            .hidratarVendasFinalizadas(limit: 120);
        await _recarregarHistorico();
        await _carregarVendas();
        final num = (r['numero'] ?? '').toString();
        _snack(
          r['autorizada'] == true
              ? 'NF-e $num autorizada no servidor.'
              : 'NF-e em processamento no servidor.',
        );
        final urlDanfe = (r['urlDanfe'] ?? '').toString();
        if (urlDanfe.isNotEmpty) {
          // ignore: discarded_futures
          launchUrl(Uri.parse(urlDanfe), mode: LaunchMode.externalApplication);
        }
      } else {
        _snack('${r['error'] ?? 'Falha ao emitir NF-e'}', erro: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _emitindo = false);
      _snack('Falha ao emitir NF-e: $e', erro: true);
    }
  }

  Future<void> _executarEmissaoNfe(
    Venda venda,
    FocusNfeDestinatarioNfe dest, {
    required String referencia,
  }) async {
    setState(() => _emitindo = true);
    final deviceId =
        _deviceIdSync ?? await SyncCursorStorage().obterOuCriarDeviceId();
    _deviceIdSync = deviceId;
    widget.vendaRepository.registrarNfeEmissaoEmAndamento(
      vendaId: venda.id,
      deviceId: deviceId,
      referencia: referencia,
    );

    FocusNfeEmissaoResultado resultado;
    try {
      resultado = await _focusNfe.emitirNfe(
        venda,
        destinatario: dest,
        logistica: _montarLogistica(),
        referencia: referencia,
      );
      if (!resultado.autorizada && !resultado.processando) {
        resultado = await FocusNfeReconsultaHelper.recuperarSePossivel(
          original: resultado,
          reconsultar: () => _focusNfe.consultarNfe(referencia),
        );
        if (FocusNfeService.pareceFalhaComunicacao(resultado) &&
            !resultado.autorizada &&
            !resultado.processando) {
          resultado =
              FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
            referencia: referencia,
          );
        }
      }
    } on FocusNfeConfigIncompletaException catch (e) {
      widget.vendaRepository.liberarNfeEmissaoEmAndamento(venda.id);
      if (!mounted) return;
      setState(() => _emitindo = false);
      _snack(e.message, erro: true);
      return;
    } on FocusNfeValidacaoException catch (e) {
      widget.vendaRepository.liberarNfeEmissaoEmAndamento(venda.id);
      if (!mounted) return;
      setState(() => _emitindo = false);
      _snack(e.message, erro: true);
      return;
    } catch (e) {
      try {
        final consulta = await _focusNfe.consultarNfe(referencia);
        if (consulta.autorizada || consulta.processando) {
          resultado = consulta;
        } else if (FocusNfeService.pareceFalhaComunicacao(consulta)) {
          resultado =
              FocusNfeReconsultaHelper.comoProcessandoAposFalhaComunicacao(
            referencia: referencia,
          );
        } else {
          widget.vendaRepository.liberarNfeEmissaoEmAndamento(venda.id);
          if (!mounted) return;
          setState(() => _emitindo = false);
          _snack('Erro ao emitir NF-e: $e', erro: true);
          return;
        }
      } catch (_) {
        widget.vendaRepository.liberarNfeEmissaoEmAndamento(venda.id);
        if (!mounted) return;
        setState(() => _emitindo = false);
        _snack('Erro ao emitir NF-e: $e', erro: true);
        return;
      }
    }

    if (!resultado.autorizada && !resultado.processando) {
      widget.vendaRepository.liberarNfeEmissaoEmAndamento(venda.id);
    }

    if (!mounted) return;
    setState(() => _emitindo = false);

    final logistica = _montarLogistica();
    final registro = NfeSaidaFiscalRegistro(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      vendaId: venda.id,
      numeroOrcamento: venda.numeroOrcamento > 0 ? venda.numeroOrcamento : venda.id,
      clienteNome: _cliente?.nomeRazao ?? 'Sem cliente',
      referenciaFocus: resultado.referencia.isNotEmpty
          ? resultado.referencia
          : referencia,
      statusFocus: resultado.statusFocus,
      emitidaEm: DateTime.now(),
      statusSefaz: resultado.statusSefaz,
      chaveNfe: resultado.chaveNfe,
      numero: resultado.numero,
      serie: resultado.serie,
      protocolo: resultado.protocolo,
      urlDanfe: resultado.urlDanfe,
      urlXml: resultado.urlXml,
      urlXmlEventoCancelamento: resultado.urlXmlCancelamento,
      mensagemSefaz: resultado.mensagem,
      modalidadeFrete: logistica.modalidadeFrete,
      placaVeiculo: logistica.placaVeiculo,
      volumes: logistica.volumes,
      pesoBrutoKg: logistica.pesoBrutoKg,
      valorTotal: venda.total,
    );
    _persistirRegistro(registro);
    _recarregarHistorico();
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeEmitir,
      entidadeId: registro.referenciaFocus,
      resumo: resultado.autorizada
          ? 'NF-e autorizada venda ${venda.id}'
          : (resultado.processando
              ? 'NF-e enviada (processando) venda ${venda.id}'
              : 'NF-e rejeitada venda ${venda.id}'),
      detalhes: {
        'vendaId': venda.id,
        'status': resultado.statusFocus,
        'numero': resultado.numero,
      },
    );

    if (resultado.autorizada) {
      await _dialogoSucessoNfe(registro);
    } else if (resultado.processando) {
      await _dialogoProcessandoNfe(registro);
    } else {
      await _dialogoErroNfe(resultado.mensagem);
    }
  }

  LanApiClient? get _apiClient => MainMenuDeps.maybeOf(context)?.lanApiClient;

  Future<void> _reconsultar(NfeSaidaFiscalRegistro reg) async {
    if (_viaApi) {
      final client = _apiClient;
      if (client == null) {
        _snack('API do servidor indisponivel.', erro: true);
        return;
      }
      setState(() => _emitindo = true);
      try {
        final r = await client.reconsultarNfeSaida(reg.referenciaFocus);
        if (!mounted) return;
        setState(() => _emitindo = false);
        await _recarregarHistorico();
        if (r['ok'] != true) {
          _snack('${r['error'] ?? 'Falha na reconsulta'}', erro: true);
          return;
        }
        final auth = r['autorizada'] == true;
        _snack(
          auth
              ? 'NF-e autorizada na reconsulta. Estoque atualizado.'
              : 'Status atualizado: ${r['status'] ?? ''}',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _emitindo = false);
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
      }
      return;
    }
    setState(() => _emitindo = true);
    final r = await _focusNfe.consultarNfe(reg.referenciaFocus);
    if (!mounted) return;
    var atualizado = mesclarRegistroComResultadoFocus(reg, r);
    final storePath =
        (widget.vendaRepository as VendaRepository).objectBox.storeDirectoryPath;
    atualizado = await reconsultarCartasCorrecaoPendentes(
      registro: atualizado,
      focusNfe: _focusNfe,
      storeDirectoryPath: storePath,
    );
    setState(() => _emitindo = false);

    _persistirRegistro(atualizado);
    _recarregarHistorico();
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeReconsultar,
      entidadeId: reg.referenciaFocus,
      resumo: 'Reconsulta NF-e — ${atualizado.rotuloStatus}',
      detalhes: {'vendaId': reg.vendaId},
    );
    if (atualizado.autorizada) {
      _snack('NF-e autorizada na reconsulta. Estoque atualizado.');
    } else {
      _snack('Status atualizado: ${atualizado.rotuloStatus}');
    }
  }

  Future<void> _reconsultarTodasProcessando() async {
    if (_viaApi) {
      final client = _apiClient;
      if (client == null || _pendenciasProcessando.isEmpty) return;
      setState(() => _emitindo = true);
      try {
        final r = await client.reconsultarNfeSaidaProcessando();
        if (!mounted) return;
        setState(() => _emitindo = false);
        await _recarregarHistorico();
        final ok = (r['autorizadas'] as num?)?.toInt() ?? 0;
        final total = (r['total'] as num?)?.toInt() ?? 0;
        _snack(
          ok > 0
              ? '$ok nota(s) autorizada(s) apos reconsulta em lote.'
              : total == 0
                  ? 'Nenhuma NF-e processando.'
                  : 'Reconsulta em lote concluida. Verifique o historico.',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _emitindo = false);
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha na reconsulta');
      }
      return;
    }
    final fila = List<NfeSaidaFiscalRegistro>.from(_pendenciasProcessando);
    if (fila.isEmpty) return;
    setState(() => _emitindo = true);
    var ok = 0;
    final storePath =
        (widget.vendaRepository as VendaRepository).objectBox.storeDirectoryPath;
    for (final reg in fila) {
      final r = await _focusNfe.consultarNfe(reg.referenciaFocus);
      if (!mounted) return;
      var atualizado = mesclarRegistroComResultadoFocus(reg, r);
      atualizado = await reconsultarCartasCorrecaoPendentes(
        registro: atualizado,
        focusNfe: _focusNfe,
        storeDirectoryPath: storePath,
      );
      _persistirRegistro(atualizado);
      if (atualizado.autorizada) {
        ok++;
      }
    }
    if (!mounted) return;
    setState(() => _emitindo = false);
    _recarregarHistorico();
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeReconsultarLote,
      resumo: 'Reconsulta em lote: $ok autorizada(s) de ${fila.length}',
    );
    _snack(
      ok > 0
          ? '$ok nota(s) autorizada(s) apos reconsulta em lote.'
          : 'Reconsulta em lote concluida. Verifique o historico.',
    );
  }

  Future<void> _exportarHistoricoCsv() async {
    if (_historico.isEmpty) {
      _snack('Nenhum registro para exportar.', erro: true);
      return;
    }
    final csv = NfeHistoricoCsvExport.gerar(_historicoFiltrado);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar historico NF-e (CSV)',
      fileName: 'nfe_saida_${DateTime.now().millisecondsSinceEpoch}.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (path == null || !mounted) return;
    try {
      await File(path).writeAsString(csv);
      _snack('CSV exportado: $path');
    } catch (e) {
      _snack('Falha ao salvar CSV: $e', erro: true);
    }
  }

  void _abrirFechamentoContabil() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExportarFechamentoPage(
          vendaRepository: widget.vendaRepository,
        ),
      ),
    );
  }

  void _abrirRelatorioFiscal() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RelatorioFiscalMensalPage(
          vendaRepository: widget.vendaRepository,
        ),
      ),
    );
  }

  void _abrirInutilizacaoNumeracao() {
    final nfeStore = _historicoStore;
    final inutStore = _inutilizacaoStore;
    if (nfeStore == null || inutStore == null) {
      _snack(
        'Inutilizacao de numeracao deve ser feita no PC servidor.',
        erro: true,
      );
      return;
    }
    showNfeInutilizacaoDialog(
      context: context,
      focusNfe: _focusNfe,
      usuarioLogin: widget.usuarioLogado.login,
      nfeStore: nfeStore,
      inutilizacaoStore: inutStore,
    ).then((_) {
      if (mounted) _recarregarHistorico();
    });
  }

  void _abrirHistoricoInutilizacao() {
    final inutStore = _inutilizacaoStore;
    if (inutStore == null) {
      _snack(
        'Historico de inutilizacao disponivel no PC servidor.',
        erro: true,
      );
      return;
    }
    showNfeInutilizacaoHistoricoDialog(
      context,
      inutStore,
      focusNfe: _focusNfe,
    );
  }

  Future<void> _enviarEmailNfe(NfeSaidaFiscalRegistro reg) async {
    if (!reg.autorizada) return;
    if (_viaApi && !widget.configuracoesService.fiscalEmCache.configurado) {
      _snack(
        'Envio de e-mail da NF-e pelo Focus exige configuracao fiscal '
        'local ou use o PC servidor.',
        erro: true,
      );
      return;
    }
    final ok = await showNfeEnviarEmailDialog(
      context: context,
      focusNfe: _focusNfe,
      referenciaFocus: reg.referenciaFocus,
      emailsSugeridos: emailsSugeridosDaVenda(
        widget.vendaRepository,
        reg.vendaId,
        clienteRepository: widget.clienteRepository,
      ),
    );
    if (ok == true) {
      _registrarAuditoriaNfe(
        acao: AuditoriaAcao.nfeEmail,
        entidadeId: reg.referenciaFocus,
        resumo: 'E-mail NF-e venda ${reg.vendaId}',
        detalhes: {'numero': reg.numero},
      );
    }
  }

  Future<void> _enviarWhatsappNfe(NfeSaidaFiscalRegistro reg) async {
    if (!reg.autorizada || reg.urlDanfe.trim().isEmpty) return;
    final venda = widget.vendaRepository.obterPorId(reg.vendaId);
    final cliente = venda == null
        ? null
        : VendaRelacaoSafe.cliente(
            venda,
            clienteRepository: widget.clienteRepository,
          );
    final tel = NfeWhatsappHelper.telefoneCliente(cliente);
    if (tel == null) {
      _snack('Cliente sem WhatsApp/telefone cadastrado.', erro: true);
      return;
    }
    final msg = NfeWhatsappHelper.montarMensagemDanfe(
      clienteNome: reg.clienteNome.isNotEmpty
          ? reg.clienteNome
          : (cliente?.nomeRazao ?? ''),
      numeroNfe: reg.numero,
      urlDanfe: reg.urlDanfe,
      chave: reg.chaveNfe,
    );
    final uri = NfeWhatsappHelper.uriWhatsapp(telefone: tel, mensagem: msg);
    if (uri == null) {
      _snack('Telefone invalido para WhatsApp.', erro: true);
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Nao foi possivel abrir o WhatsApp.', erro: true);
      return;
    }
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeWhatsapp,
      entidadeId: reg.referenciaFocus,
      resumo: 'WhatsApp DANFE venda ${reg.vendaId}',
    );
  }

  Future<void> _emitirVendaPendencia(Venda venda) async {
    _tabs.animateTo(0);
    _buscaVendaController.text =
        '${VendaDocumentoRotuloHelper.numeroControleInterno(venda)}';
    await _buscarVendaPorNumero();
  }

  List<NfeSaidaFiscalRegistro> get _historicoFiltrado =>
      NfeHistoricoFiltroUtil.aplicar(_historico, _filtroHistorico);

  Future<void> _cancelarNfe(NfeSaidaFiscalRegistro reg) async {
    if (!await _garantirPermissaoCancelarNfe()) return;
    final just = await showNfeCancelamentoDialog(context);
    if (just == null || !mounted) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cancelamento'),
        content: Text(
          'Cancelar NF-e ${reg.numero.isNotEmpty ? reg.numero : reg.referenciaFocus}?\n\n'
          'Esta acao e irreversivel na SEFAZ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar nota'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    if (_viaApi) {
      final client = _apiClient;
      if (client == null) {
        _snack('API do servidor indisponivel.', erro: true);
        return;
      }
      setState(() => _emitindo = true);
      try {
        final r = await client.cancelarNfeSaida(
          referencia: reg.referenciaFocus,
          justificativa: just,
        );
        if (!mounted) return;
        setState(() => _emitindo = false);
        if (r['ok'] != true) {
          await _dialogoErroNfe(
            (r['error'] ?? 'Cancelamento nao aceito pela SEFAZ.').toString(),
          );
          return;
        }
        await _recarregarHistorico();
        _snack(
          (r['mensagem'] ??
                  (r['cancelada'] == true
                      ? 'NF-e cancelada na SEFAZ.'
                      : 'Solicitacao enviada.'))
              .toString(),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _emitindo = false);
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao cancelar');
      }
      return;
    }

    setState(() => _emitindo = true);
    final r = await _focusNfe.cancelarNfe(
      reg.referenciaFocus,
      justificativa: just,
    );
    if (!mounted) return;
    setState(() => _emitindo = false);

    if (r.rejeitada && !r.cancelada) {
      await _dialogoErroNfe(
        r.mensagem.isNotEmpty ? r.mensagem : 'Cancelamento nao aceito pela SEFAZ.',
      );
      return;
    }

    final atualizado = mesclarRegistroComResultadoFocus(reg, r);
    _persistirRegistro(atualizado);
    _recarregarHistorico();
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeCancelar,
      entidadeId: reg.referenciaFocus,
      resumo: 'Cancelamento NF-e venda ${reg.vendaId}',
      detalhes: {'status': atualizado.rotuloStatus},
    );
    _snack(
      atualizado.cancelada
          ? 'NF-e cancelada na SEFAZ.'
          : 'Solicitacao enviada: ${atualizado.rotuloStatus}',
    );
  }

  Future<void> _emitirCartaCorrecao(NfeSaidaFiscalRegistro reg) async {
    if (!await _garantirPermissaoCancelarNfe()) return;
    final texto = await showNfeCartaCorrecaoDialog(context);
    if (texto == null || !mounted) return;

    if (_viaApi) {
      final client = _apiClient;
      if (client == null) {
        _snack('API do servidor indisponivel.', erro: true);
        return;
      }
      setState(() => _emitindo = true);
      try {
        final res = await client.cartaCorrecaoNfeSaida(
          referencia: reg.referenciaFocus,
          correcao: texto,
        );
        if (!mounted) return;
        setState(() => _emitindo = false);
        if (res['ok'] != true) {
          await _dialogoErroNfe(
            (res['error'] ?? 'Falha ao emitir CC-e.').toString(),
          );
          return;
        }
        await _recarregarHistorico();
        _snack(
          (res['mensagem'] ??
                  (res['processando'] == true
                      ? 'CC-e enviada — aguardando SEFAZ.'
                      : 'CC-e registrada.'))
              .toString(),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _emitindo = false);
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha na CC-e');
      }
      return;
    }

    setState(() => _emitindo = true);
    final res = await _focusNfe.emitirCartaCorrecaoNfe(
      reg.referenciaFocus,
      correcao: texto,
    );
    if (!mounted) return;
    setState(() => _emitindo = false);

    if (!res.sucesso) {
      await _dialogoErroNfe(
        res.mensagem.isNotEmpty ? res.mensagem : 'Falha ao emitir CC-e.',
      );
      return;
    }

    final atualizado = reg.comNovaCartaCorrecao(
      NfeCartaCorrecaoRegistro(
        numeroSequencia: res.numeroSequencia > 0 ? res.numeroSequencia : 1,
        textoCorrecao: texto,
        urlPdf: res.urlPdf,
        urlXml: res.urlXml,
        protocolo: res.protocolo,
        statusFocus:
            res.statusFocus.isEmpty ? 'autorizado' : res.statusFocus,
      ),
    );
    _persistirRegistro(atualizado);
    if (reg.chaveNfe.trim().length >= 40 && res.urlXml.trim().isNotEmpty) {
      unawaited(
        NfeCceXmlLocalService.arquivarOuEnfileirar(
          storeDirectoryPath:
              (widget.vendaRepository as VendaRepository)
                  .objectBox
                  .storeDirectoryPath,
          chaveAcesso: reg.chaveNfe,
          numeroSequencia: res.numeroSequencia > 0 ? res.numeroSequencia : 1,
          urlXml: res.urlXml,
        ),
      );
    }
    _recarregarHistorico();
    _registrarAuditoriaNfe(
      acao: AuditoriaAcao.nfeCartaCorrecao,
      entidadeId: reg.referenciaFocus,
      resumo: 'CC-e #${res.numeroSequencia} NF-e venda ${reg.vendaId}',
      detalhes: {
        'sequencia': res.numeroSequencia,
        if (res.processando) 'processando': true,
      },
    );
    _snack(
      res.processando
          ? 'CC-e enviada — aguardando SEFAZ.'
          : (res.mensagem.isNotEmpty ? res.mensagem : 'CC-e registrada.'),
    );
  }

  Future<void> _reemitirVenda(NfeSaidaFiscalRegistro reg) async {
    final vendaId = reg.vendaId;
    if (vendaId > 0) {
      final venda = widget.vendaRepository.obterPorId(vendaId);
      if (venda != null && venda.nfe55Autorizada) {
        _recarregarHistorico();
        _snack(
          'Esta venda ja possui NF-e autorizada'
          '${venda.nfeNumero.trim().isNotEmpty ? " (nota ${venda.nfeNumero.trim()})" : ""}. '
          'Nao e necessario reemitir — consulte o historico.',
        );
        return;
      }
      if (_vendaComNfeAutorizada[vendaId] == true) {
        _recarregarHistorico();
        _snack(
          'Esta venda ja possui NF-e autorizada no historico. '
          'Nao e necessario reemitir.',
        );
        return;
      }
    }

    final id = vendaId > 0 ? vendaId : reg.numeroOrcamento;
    if (id <= 0) {
      _snack('Registro sem venda vinculada.', erro: true);
      return;
    }
    _tabs.animateTo(0);
    _buscaVendaController.text = '$id';
    await _buscarVendaPorNumero();
    if (!mounted) return;
    _snack(
      'Venda carregada na aba Emitir. Revise os dados e emita uma nova NF-e.',
    );
  }

  Future<void> _escolherPeriodoHistorico() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _filtroHistorico.dataInicio != null &&
              _filtroHistorico.dataFim != null
          ? DateTimeRange(
              start: _filtroHistorico.dataInicio!,
              end: _filtroHistorico.dataFim!,
            )
          : null,
      locale: const Locale('pt', 'BR'),
    );
    if (range == null || !mounted) return;
    setState(() {
      _filtroHistorico = NfeHistoricoFiltro(
        textoBusca: _filtroHistorico.textoBusca,
        status: _filtroHistorico.status,
        dataInicio: range.start,
        dataFim: range.end,
      );
    });
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _snack('URL invalida.', erro: true);
      return;
    }
    if (Platform.isWindows) {
      try {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
        return;
      } catch (_) {}
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Nao foi possivel abrir o link.', erro: true);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Theme.of(context).colorScheme.error : null,
        duration: Duration(seconds: erro ? 8 : 4),
      ),
    );
  }

  String _formatarMoeda(double v) => 'R\$ ${_currency.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('NF-e de Saida (Modelo 55)'),
        actions: [
          IconButton(
            tooltip: 'Relatorio do mes',
            onPressed: _abrirRelatorioFiscal,
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: 'Historico inutilizacoes',
            onPressed: _abrirHistoricoInutilizacao,
            icon: const Icon(Icons.history_toggle_off_outlined),
          ),
          IconButton(
            tooltip: 'Inutilizar numeracao',
            onPressed: _abrirInutilizacaoNumeracao,
            icon: const Icon(Icons.block_outlined),
          ),
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: _historico.isEmpty ? null : _exportarHistoricoCsv,
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: 'Fechamento contabil',
            onPressed: _abrirFechamentoContabil,
            icon: const Icon(Icons.folder_zip_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Emitir', icon: Icon(Icons.description_outlined)),
            Tab(
              text: 'Pendencias',
              icon: Badge(
                isLabelVisible: _contagemPendenciasOperacionais > 0,
                label: Text('$_contagemPendenciasOperacionais'),
                child: const Icon(Icons.pending_actions_outlined),
              ),
            ),
            const Tab(text: 'Historico', icon: Icon(Icons.history_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          const NfeAmbienteBanner(),
          NfePainelResumoBar(resumo: _resumo),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabs,
                  children: [
                    _buildAbaEmitir(theme),
                    NfeAbaPendencias(
                      vendasSemNfe: _pendenciasVendas,
                      filtro: _filtroPendencias,
                      onFiltroChanged: (f) {
                        setState(() => _filtroPendencias = f);
                        _recarregarHistorico();
                      },
                      processando: _pendenciasProcessando,
                      rejeitadas: _pendenciasRejeitadas,
                      emitindo: _emitindo,
                      onEmitirVenda: _emitirVendaPendencia,
                      onReconsultar: _reconsultar,
                      onReconsultarTodas: _reconsultarTodasProcessando,
                      onVerDetalheRegistro: (r) =>
                          showNfeRegistroDetalheDialog(context, r),
                      onReemitirRegistro: _reemitirVenda,
                      onVerErroRegistro: (r) => _dialogoErroNfe(
                        r.mensagemSefaz,
                        registro: r,
                      ),
                    ),
                    _buildAbaHistorico(theme),
                  ],
                ),
                if (_emitindo)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'Comunicando com a SEFAZ através da Focus NFe...',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaEmitir(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Vendas finalizadas',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscaVendaController,
                          decoration: const InputDecoration(
                            labelText: 'Orcamento / ID',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: (_) => _buscarVendaPorNumero(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Buscar',
                        onPressed: _buscarVendaPorNumero,
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _carregandoVendas
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _vendasElegiveis.length,
                          itemBuilder: (ctx, i) {
                            final v = _vendasElegiveis[i];
                            final sel = _vendaSelecionada?.id == v.id;
                            final temNfe = _vendaComNfeAutorizada[v.id] == true;
                            return ListTile(
                              selected: sel,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      VendaDocumentoRotuloHelper
                                          .rotuloTituloLista(v),
                                    ),
                                  ),
                                  if (temNfe)
                                    Tooltip(
                                      message: 'NF-e autorizada',
                                      child: Icon(
                                        Icons.verified_outlined,
                                        size: 18,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${_formatarMoeda(v.total)} · '
                                '${DateFormat('dd/MM/yy HH:mm').format(v.data.toLocal())}',
                              ),
                              onTap: () => _selecionarVenda(v),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _vendaSelecionada == null
              ? Center(
                  child: Text(
                    'Selecione uma venda para conferir os dados da NF-e.',
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildPainelConferencia(theme),
                ),
        ),
      ],
    );
  }

  Widget _buildPainelConferencia(ThemeData theme) {
    final v = _vendaSelecionada!;
    final c = _cliente;
    final doc = c?.documento.replaceAll(RegExp(r'\D'), '') ?? '';
    final pj = doc.length == 14;
    final pre = _preEmissao;
    final podeEmitir = pre?.podeEmitir == true && !_carregandoDados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Conferencia pre-emissao — '
          '${VendaDocumentoRotuloHelper.rotuloControleInterno(v)}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Emissao NF-e 55; ao autorizar, estoque e controle interno sao '
          'registrados automaticamente.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        if (pre != null) ...[
          NfeChecklistPanel(
            resultado: pre,
            podeEmitir: pre.podeEmitir,
          ),
          const SizedBox(height: 12),
        ],
        _secaoCard(
          theme,
          titulo: 'Emitente (loja)',
          icon: Icons.store_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_empresa?.nomeLoja ?? 'Loja'),
              if (_empresa != null && _empresa!.endereco.trim().isNotEmpty)
                Text(_empresa!.endereco, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _secaoCard(
          theme,
          titulo: 'Destinatario (cliente)',
          icon: Icons.person_outline,
          child: _carregandoDados
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c == null)
                      Text(
                        'Sem cliente vinculado a esta venda.',
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    else ...[
                      Row(
                        children: [
                          Chip(
                            label: Text(pj ? 'Pessoa Juridica' : 'Pessoa Fisica'),
                            backgroundColor: pj
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.secondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.nomeRazao,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      Text('Documento: ${c.documento}'),
                      if (pj && c.inscricaoEstadual.trim().isNotEmpty)
                        Text('Inscricao Estadual: ${c.inscricaoEstadual}'),
                      Text(
                        'Indicador IE: ${_rotuloIndicadorIe(c)} · '
                        'UF destino: ${pre?.ufDestinatario ?? FiscalConfig.ufEmitente}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_ibgeResolvido?.endereco != null)
                        Text(_ibgeResolvido!.endereco!.resumo()),
                      const SizedBox(height: 6),
                      Text(
                        _statusIbge,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _ibgeResolvido?.sucesso == true
                              ? Colors.green.shade700
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _secaoCard(
          theme,
          titulo: 'Logistica / transporte',
          icon: Icons.local_shipping_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 9,
                    label: Text('Sem transporte'),
                    tooltip: 'Retirada na loja (modalidade 9)',
                  ),
                  ButtonSegment(
                    value: 0,
                    label: Text('CIF'),
                    tooltip: 'Frete por conta do emitente',
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('FOB'),
                    tooltip: 'Frete por conta do destinatario',
                  ),
                ],
                selected: {_modalidadeFrete},
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  setState(() => _modalidadeFrete = s.first);
                },
              ),
              if (_logisticaDica.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _vendaSelecionada == null
                        ? null
                        : () {
                            setState(() {
                              _aplicarLogisticaSugerida(_vendaSelecionada!);
                            });
                          },
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Recalcular sugestao'),
                  ),
                ),
                Text(
                  _logisticaDica,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _modalidadeFrete == 9
                        ? Colors.blueGrey.shade700
                        : Colors.green.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (_vendaSelecionada != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Entrega: ${EntregaVendaHelper.textoEntregaCabecalhoVenda(_vendaSelecionada!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _placaController,
                decoration: InputDecoration(
                  labelText: 'Placa do caminhao',
                  hintText: 'ABC1D23',
                  isDense: true,
                  helperText: _modalidadeFrete == 9
                      ? 'Opcional na retirada (modalidade 9)'
                      : 'Preencha se a loja transportar',
                ),
                textCapitalization: TextCapitalization.characters,
                enabled: _modalidadeFrete != 9,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _volumesController,
                      decoration: const InputDecoration(
                        labelText: 'Volumes',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _pesoController,
                      decoration: const InputDecoration(
                        labelText: 'Peso bruto (kg)',
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _modalidadeFrete == 9
                    ? 'Retirada na loja: volumes/peso minimos para o layout da NF-e.'
                    : 'Volumes e peso dos itens de carreto/entrega (estimativa).',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (pre != null && pre.linhasFiscais.isNotEmpty) ...[
          NfeItensFiscaisTable(
            linhas: pre.linhasFiscais,
            onAbrirProduto: (id) {
              _snack(
                'Produto ID $id — abra Cadastros > Produtos para ajustar NCM/CEST.',
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (pre != null)
          NfeCobrancaResumoPanel(
            venda: v,
            valorCobranca: pre.valorCobrancaPrazo,
          ),
        if (pre != null && pre.valorCobrancaPrazo > 0)
          const SizedBox(height: 12),
        _secaoCard(
          theme,
          titulo: 'Totais da nota',
          icon: Icons.payments_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total venda: ${_formatarMoeda(v.total)}'),
              Text('Itens: ${_itensDaVenda(v).length}'),
              if (v.valorFrete > 0)
                Text('Frete: ${_formatarMoeda(v.valorFrete)}'),
              if (v.descontoImplicitoTotal > 0)
                Text('Desconto: ${_formatarMoeda(v.descontoImplicitoTotal)}'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                podeEmitir
                    ? 'Passo 1: checklist verde. Passo 2: revise DANFe e confirme.'
                    : 'Resolva as pendencias vermelhas no checklist e na tabela de itens.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: podeEmitir
                      ? Colors.green.shade800
                      : theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _emitindo || !podeEmitir ? null : _revisarEConfirmarEmissao,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Revisar e emitir NF-e'),
            ),
          ],
        ),
      ],
    );
  }

  String _rotuloIndicadorIe(Cliente cliente) {
    final ind = cliente.indicadorIe.trim().toLowerCase();
    if (ind == 'contribuinte') return 'Contribuinte ICMS';
    if (ind == 'isento') return 'Isento';
    if (cliente.inscricaoEstadual.replaceAll(RegExp(r'\D'), '').isNotEmpty) {
      return 'Contribuinte (IE cadastrada)';
    }
    return 'Nao contribuinte';
  }

  Widget _secaoCard(
    ThemeData theme, {
    required String titulo,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(titulo, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildAbaHistorico(ThemeData theme) {
    if (_historico.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma NF-e de saida registrada ainda.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    final filtrados = _historicoFiltrado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NfeHistoricoFiltrosBar(
          filtro: _filtroHistorico,
          buscaController: _historicoBuscaController,
          totalRegistros: _historico.length,
          totalFiltrados: filtrados.length,
          onFiltroChanged: (f) => setState(() => _filtroHistorico = f),
          onLimparPeriodo: () => setState(
            () => _filtroHistorico = NfeHistoricoFiltro(
              textoBusca: _filtroHistorico.textoBusca,
              status: _filtroHistorico.status,
            ),
          ),
          onEscolherPeriodo: _escolherPeriodoHistorico,
        ),
        if (_emitindo)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: filtrados.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum registro com os filtros aplicados.',
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtrados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final r = filtrados[i];
                    return GestureDetector(
                      onLongPress: () => showNfeRegistroDetalheDialog(context, r),
                      child: NfeHistoricoCard(
                      registro: r,
                      emitindo: _emitindo,
                      onAbrirDanfe: () => _abrirUrl(r.urlDanfe),
                      onAbrirXml: () => _abrirUrl(r.urlXml),
                      onAbrirXmlCancelamento: r.urlXmlEventoCancelamento.isNotEmpty
                          ? () => _abrirUrl(r.urlXmlEventoCancelamento)
                          : null,
                      onReconsultar: () => _reconsultar(r),
                      onVerErro: () => _dialogoErroNfe(r.mensagemSefaz),
                      onCancelar: () => _cancelarNfe(r),
                      onCartaCorrecao: () => _emitirCartaCorrecao(r),
                      onReemitir: () => _reemitirVenda(r),
                      onEnviarEmail: () => _enviarEmailNfe(r),
                      onEnviarWhatsapp: () => _enviarWhatsappNfe(r),
                      onAbrirPdfCce: (cce) => _abrirUrl(cce.urlPdf),
                      onAbrirXmlCce: (cce) => _abrirUrl(cce.urlXml),
                    ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _dialogoSucessoNfe(NfeSaidaFiscalRegistro r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: Theme.of(ctx).colorScheme.primary),
        title: const Text('NF-e autorizada'),
        content: Text(
          'Nota ${r.numero.isNotEmpty ? r.numero : r.referenciaFocus} autorizada.\n'
          '${r.mensagemSefaz}',
        ),
        actions: [
          if (r.urlDanfe.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _abrirUrl(r.urlDanfe);
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Imprimir DANFE (NF-e)'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoProcessandoNfe(NfeSaidaFiscalRegistro r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('NF-e em processamento'),
        content: Text(
          'A nota foi enviada e aguarda retorno da SEFAZ.\n'
          'Referencia: ${r.referenciaFocus}\n\n'
          'Use Reconsultar no historico quando o servico normalizar.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoErroNfe(
    String mensagem, {
    NfeSaidaFiscalRegistro? registro,
  }) async {
    await FiscalRejeicaoDetalheDialog.show(
      context,
      titulo: 'Detalhes da Rejeicao Fiscal',
      numeroControle: registro != null
          ? '${VendaDocumentoRotuloHelper.rotuloControlePorNumero(registro.numeroOrcamento)} · ${registro.clienteNome}'
          : '—',
      statusFiscal: registro?.rotuloStatus ?? 'Rejeitada',
      mensagemErro: mensagem,
    );
  }
}

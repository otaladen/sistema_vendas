import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'domain/auditoria_catalogo.dart';
import 'domain/lote_validade_config.dart';
import 'domain/modo_terminal_leve.dart';
import 'data/api/cliente_api_repository.dart';
import 'data/api/conta_pagar_api_repository.dart';
import 'data/api/fornecedor_api_repository.dart';
import 'data/api/funcionario_api_repository.dart';
import 'data/api/kit_promocao_api_repository.dart';
import 'data/api/lan_api_client.dart';
import 'data/api/lan_api_event_hub.dart';
import 'data/api/lan_api_url.dart';
import 'data/api/lista_compra_api_repository.dart';
import 'data/api/nfe_importada_api_repository.dart';
import 'data/api/produto_api_repository.dart';
import 'data/api/recado_loja_api_repository.dart';
import 'data/api/usuario_api_repository.dart';
import 'data/api/venda_api_repository.dart';
import 'data/sync/sync_entity_codec_extras.dart';
import 'data/api/vendedor_api_repository.dart';
import 'services/entrega_baixa_sync_service.dart';
import 'services/entrega_pod_lan_service.dart';
import 'data/app_config_repository.dart';
import 'data/app_fundo_repository.dart';
import 'data/app_menu_modo_repository.dart';
import 'data/app_tema_repository.dart';
import 'data/auditoria_repository.dart';
import 'data/auto_backup_service.dart';
import 'data/backup_agendado_headless_service.dart';
import 'data/backup_ao_fechar_service.dart';
import 'data/cadastro_duplicados_limpeza.dart';
import 'data/cliente_repository.dart';
import 'data/fornecedor_repository.dart';
import 'data/funcionario_repository.dart';
import 'data/motorista_repository.dart';
import 'data/objectbox.dart';
import 'data/produto_repository.dart';
import 'data/sync/lan_sync_scheduler.dart';
import 'data/sync/sync_service.dart';
import 'data/usuario_repository.dart';
import 'data/venda_repository.dart';
import 'data/vendedor_repository.dart';
import 'model/usuario_sistema.dart';
import 'services/auditoria_registrar.dart';
import 'services/auditoria_retencao_service.dart';
import 'services/entrega_pod_retencao_service.dart';
import 'services/lan_servidor_bootstrap.dart';
import 'services/lan_servidor_headless_service.dart';
import 'services/print_service.dart';
import 'services/estoque_diagnostico_startup.dart';
import 'services/fiscal_config_store.dart';
import 'services/fiscal_reconciliacao_startup.dart';
import 'services/trusted_http_client.dart';
import 'services/windows_app_startup_helper.dart';
import 'ui/app_startup_error_page.dart';
import 'ui/app_global_error_handler.dart';
import 'ui/layout/app_layout.dart';
import 'ui/login_page.dart';
import 'ui/main_menu_page.dart';
import 'ui/terminal_config_page.dart';
import 'ui/theme/app_fundo_camada.dart';
import 'ui/theme/app_fundo_id.dart';
import 'ui/theme/app_fundo_scope.dart';
import 'ui/theme/app_menu_modo_id.dart';
import 'ui/theme/app_menu_modo_scope.dart';
import 'ui/theme/app_tema_id.dart';
import 'ui/theme/app_tema_scope.dart';
import 'ui/theme/app_theme_builder.dart';
import 'ui/widgets/chat/chat_interno_hub.dart';

export 'ui/theme/app_semantic_colors.dart';

Future<void> main(List<String> args) async {
  if (BackupAgendadoHeadlessService.deveExecutar(args)) {
    final code = await BackupAgendadoHeadlessService.executar();
    exit(code);
  }

  // Servidor de terminais sem janela (sobe com o Windows).
  if (LanServidorHeadlessService.deveExecutar(args)) {
    WidgetsFlutterBinding.ensureInitialized();
    configurarHttpOverridesPlataforma();
    final code = await LanServidorHeadlessService.executarEManterVivo();
    exit(code);
  }

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      silenciarDebugPrintEmProducao();
      configurarTratamentoErrosGlobais();
      configurarHttpOverridesPlataforma();
      await initializeDateFormatting('pt_BR');
      await _tentarSincronizarHorarioSistemaNoInicio();

      final appConfigRepository = AppConfigRepository();
      await FiscalConfigStore.carregar();
      await LoteValidadeConfigStore.carregar();
      final empresaCfg = await appConfigRepository.carregarEmpresaConfig();
      await FiscalConfigStore.aplicarRegimeEmpresa(
        empresaCfg.regimeTributarioEmitente,
      );

      // Terminal leve (Windows cliente): abre sem ObjectBox / sem bootstrap.
      if (modoTerminalLeveAtivo(empresaCfg)) {
        unawaited(
          EntregaPodRetencaoService.aplicarSeConfigurado(appConfigRepository),
        );
        runApp(
          MyApp(
            objectBox: null,
            syncService: null,
            lanSyncScheduler: null,
            appConfigRepository: appConfigRepository,
            terminalLeve: true,
          ),
        );
        return;
      }

      // Se o servidor headless estiver rodando, libera o banco para a UI.
      if (Platform.isWindows) {
        await LanServidorHeadlessService.pararInstanciaSeExistir();
      }

      ObjectBox objectBox;
      try {
        objectBox = await ObjectBox.create();
      } catch (e, st) {
        runApp(
          AppStartupErrorPage(
            erro: 'Falha ao abrir banco local (ObjectBox):\n$e\n\n$st',
          ),
        );
        return;
      }

      final auditoriaRepository = AuditoriaRepository(objectBox);
      AuditoriaRegistrar.inicializar(auditoriaRepository);
      await FiscalReconciliacaoStartup.executarSeConfigurado(
        objectBox: objectBox,
      );
      await EstoqueDiagnosticoStartup.executarSePossivel(
        objectBox: objectBox,
      );
      await AuditoriaRetencaoService.aplicarSeConfigurado(
        configRepository: appConfigRepository,
        auditoriaRepository: auditoriaRepository,
      );
      unawaited(
        EntregaPodRetencaoService.aplicarSeConfigurado(appConfigRepository),
      );
      await _executarMigracaoMotoristaEntrega(
        objectBox: objectBox,
        configRepository: appConfigRepository,
      );
      await _executarMigracaoSkuZerosEsquerda(
        objectBox: objectBox,
        configRepository: appConfigRepository,
      );
      await _executarMigracaoCadastroDuplicados(
        objectBox: objectBox,
        configRepository: appConfigRepository,
      );

      // Windows/Android/iOS servidor: ObjectBox + LanApi.
      // Terminal Leve (PC ou celular com rede ativa): sem ObjectBox — ver ramo acima.
      // SyncService/LanSyncScheduler: so aparelho mobile em modo local (sem rede).
      SyncService? syncService;
      LanSyncScheduler? lanSyncScheduler;
      if (!Platform.isWindows &&
          (Platform.isAndroid || Platform.isIOS)) {
        syncService = SyncService(
          objectBox: objectBox,
          configRepository: appConfigRepository,
        );
        lanSyncScheduler = LanSyncScheduler(syncService: syncService);
      }

      runApp(
        MyApp(
          objectBox: objectBox,
          syncService: syncService,
          lanSyncScheduler: lanSyncScheduler,
          appConfigRepository: appConfigRepository,
          terminalLeve: false,
        ),
      );
    },
    (error, stack) {
      reportarErroGlobal(error, stack);
    },
  );
}

Future<void> _executarMigracaoMotoristaEntrega({
  required ObjectBox objectBox,
  required AppConfigRepository configRepository,
}) async {
  final jaConcluida = await configRepository.migracaoMotoristaEntregaConcluida();
  if (jaConcluida) return;
  final vendaRepository = VendaRepository(objectBox);
  vendaRepository.migrarMotoristaEntregaLegado();
  await configRepository.marcarMigracaoMotoristaEntregaConcluida();
}

Future<void> _executarMigracaoSkuZerosEsquerda({
  required ObjectBox objectBox,
  required AppConfigRepository configRepository,
}) async {
  final jaConcluida = await configRepository.migracaoSkuZerosEsquerdaConcluida();
  if (jaConcluida) return;
  ProdutoRepository(objectBox).migrarSkuZerosEsquerdaLegado();
  await configRepository.marcarMigracaoSkuZerosEsquerdaConcluida();
}

Future<void> _executarMigracaoCadastroDuplicados({
  required ObjectBox objectBox,
  required AppConfigRepository configRepository,
}) async {
  final jaConcluida =
      await configRepository.migracaoCadastroDuplicadosConcluida();
  if (jaConcluida) return;
  try {
    final r = await CadastroDuplicadosLimpeza.executar(objectBox);
    if (r.houveLimpeza) {
      debugPrint('Limpeza cadastros duplicados: $r');
    }
  } catch (e, st) {
    debugPrint('Falha na limpeza de cadastros duplicados: $e\n$st');
  }
  await configRepository.marcarMigracaoCadastroDuplicadosConcluida();
}

Future<void> _tentarSincronizarHorarioSistemaNoInicio() async {
  if (!Platform.isWindows) {
    return;
  }
  try {
    await Process.run(
      'w32tm',
      ['/resync'],
      runInShell: true,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {}
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.objectBox,
    required this.syncService,
    required this.lanSyncScheduler,
    required this.appConfigRepository,
    this.terminalLeve = false,
  });

  final ObjectBox? objectBox;
  final SyncService? syncService;
  final LanSyncScheduler? lanSyncScheduler;
  final AppConfigRepository appConfigRepository;
  final bool terminalLeve;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  UsuarioSistema? _usuarioLogado;
  AppTemaId _temaAtual = AppTemaId.verde;
  AppMenuModoId _menuModoAtual = AppMenuModoId.classico;
  AppFundoId _fundoAtual = AppFundoId.liso;
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  Timer? _timerBackupAutomatico;
  Timer? _debounceEventoApi;
  Timer? _debounceProdutoApi;
  final Set<String> _entidadesApiPendentes = {};
  List<int> _produtoIdsApiPendentes = const [];
  int? _produtoRevisionPendente;
  late final PrintService _printService;

  bool _terminalPrecisaConfig = false;
  bool _terminalHidratando = false;
  bool _terminalCarregandoDados = false;
  String? _terminalErro;

  // Repos API (terminal).
  LanApiClient? _apiClient;
  ProdutoApiRepository? _produtoApi;
  ClienteApiRepository? _clienteApi;
  VendaApiRepository? _vendaApi;
  VendedorApiRepository? _vendedorApi;
  FuncionarioApiRepository? _funcionarioApi;
  MotoristaApiRepository? _motoristaApi;
  ContaPagarApiRepository? _contaPagarApi;
  KitOrcamentoApiRepository? _kitApi;
  PromocaoApiRepository? _promoApi;
  ListaCompraApiRepository? _listaCompraApi;
  UsuarioApiRepository? _usuarioApi;
  NfeImportadaApiRepository? _nfeImportadaApi;
  RecadoLojaApiRepository? _recadoLojaApi;
  FornecedorApiRepository? _fornecedorApi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregarPersonalizacaoInicial());
    _printService = PrintService(widget.appConfigRepository);
    if (widget.terminalLeve) {
      // Conecta na API antes do login (usuarios so existem no PC servidor).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_prepararTerminalLeve());
      });
    } else if (widget.objectBox != null) {
      _timerBackupAutomatico = Timer.periodic(
        const Duration(minutes: 5),
        (_) => AutoBackupService.tentarExecutarSeDevido(
          widget.appConfigRepository,
          objectBox: widget.objectBox!,
          lanSyncScheduler: widget.lanSyncScheduler,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AutoBackupService.tentarExecutarSeDevido(
          widget.appConfigRepository,
          objectBox: widget.objectBox!,
          lanSyncScheduler: widget.lanSyncScheduler,
        );
        // PC servidor: API dos terminais sobe ja na tela de login.
        unawaited(
          LanServidorBootstrap.garantirAtivo(
            objectBox: widget.objectBox!,
            configRepository: widget.appConfigRepository,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerBackupAutomatico?.cancel();
    _debounceEventoApi?.cancel();
    _debounceProdutoApi?.cancel();
    LanApiEventHub.instance.desconectar();
    EntregaBaixaSyncService.instance.desligar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !widget.terminalLeve &&
        widget.lanSyncScheduler != null) {
      LanSyncScheduler.aoRetomarApp();
    }
    if (state == AppLifecycleState.resumed && widget.terminalLeve) {
      unawaited(EntregaBaixaSyncService.instance.aoRetomarApp());
    }
    if (state == AppLifecycleState.detached && !widget.terminalLeve) {
      unawaited(_executarBackupAoFechar());
    }
  }

  Future<void> _executarBackupAoFechar({bool agendarHeadless = true}) async {
    // Headless so ao fechar a UI. Logout/troca de usuario deixa o app aberto.
    if (agendarHeadless) {
      await WindowsAppStartupHelper.agendarHeadlessAposSaida();
    }
    if (widget.objectBox != null) {
      final nomeLoja = await _nomeLojaAtual();
      await BackupAoFecharService.tentarSeAtivo(
        repository: widget.appConfigRepository,
        objectBox: widget.objectBox!,
        lanSyncScheduler: widget.lanSyncScheduler,
        nomeLoja: nomeLoja,
      );
    }
  }

  Future<String> _nomeLojaAtual() async {
    final c = await widget.appConfigRepository.carregarEmpresaConfig();
    return c.nomeLoja;
  }

  Future<void> _carregarPersonalizacaoInicial() async {
    final results = await Future.wait([
      AppTemaRepository.carregar(),
      AppMenuModoRepository.carregar(),
      AppFundoRepository.carregar(),
    ]);
    if (!mounted) return;
    setState(() {
      _temaAtual = results[0] as AppTemaId;
      _menuModoAtual = results[1] as AppMenuModoId;
      _fundoAtual = results[2] as AppFundoId;
    });
  }

  Future<void> _definirTema(AppTemaId tema) async {
    if (!mounted) return;
    setState(() => _temaAtual = tema);
    try {
      await AppTemaRepository.salvar(tema, login: _usuarioLogado?.login);
    } catch (_) {}
  }

  Future<void> _definirMenuModo(AppMenuModoId modo) async {
    if (!mounted) return;
    setState(() => _menuModoAtual = modo);
    try {
      await AppMenuModoRepository.salvar(modo, login: _usuarioLogado?.login);
    } catch (_) {}
  }

  Future<void> _definirFundo(AppFundoId fundo) async {
    if (!mounted) return;
    setState(() => _fundoAtual = fundo);
    try {
      await AppFundoRepository.salvar(fundo, login: _usuarioLogado?.login);
    } catch (_) {}
  }

  Future<void> _entrar(UsuarioSistema usuario) async {
    AuditoriaRegistrar.definirUsuarioSessao(usuario.login);
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.autenticacao,
      acao: AuditoriaAcao.login,
      usuarioLogin: usuario.login,
      resumo: 'Login: ${usuario.nome} (${usuario.login})',
    );
    final personalizacao = await Future.wait([
      AppTemaRepository.carregar(login: usuario.login),
      AppMenuModoRepository.carregar(login: usuario.login),
      AppFundoRepository.carregar(login: usuario.login),
    ]);
    if (!mounted) return;

    if (widget.terminalLeve && _produtoApi == null) {
      await _prepararTerminalLeve();
    }
    if (widget.terminalLeve && _produtoApi != null) {
      await _hidratarTerminalPosLogin();
    }

    if (!mounted) return;
    setState(() {
      _usuarioLogado = usuario;
      _temaAtual = personalizacao[0] as AppTemaId;
      _menuModoAtual = personalizacao[1] as AppMenuModoId;
      _fundoAtual = personalizacao[2] as AppFundoId;
    });
  }

  Future<void> _prepararTerminalLeve() async {
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    final url = config.redeServidorUrl.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _terminalPrecisaConfig = true;
        _terminalHidratando = false;
        _terminalErro = null;
      });
      return;
    }
    setState(() {
      _terminalPrecisaConfig = false;
      _terminalHidratando = true;
      _terminalErro = null;
    });
    try {
      LanApiEventHub.instance.removeListener(_onApiEvento);
      LanApiEventHub.instance.desconectar();
      final apiUrl = LanApiUrl.fromSyncUrl(url);
      final client = LanApiClient(
        baseUrl: apiUrl,
        syncToken: config.redeSyncToken,
      );
      client.onFalhaRede = LanApiEventHub.instance.marcarOffline;
      client.onSucessoRede = LanApiEventHub.instance.marcarOnline;
      final ok = await client.healthOk();
      if (!ok) {
        throw StateError(
          'API do servidor inacessivel em $apiUrl (porta ${LanApiUrl.portaPadrao}).\n\n'
          'No PC 1 (servidor):\n'
          '1) Abra o Sistema de Vendas em modo servidor\n'
          '2) Deixe o app aberto (pode ficar no login)\n'
          '3) Confirme em Configuracoes > Rede que a sincronizacao esta ativa\n'
          '4) Libere a porta ${LanApiUrl.portaPadrao} no firewall\n\n'
          'Dica: use o IP do PC servidor (nao o do roteador 192.168.x.1). '
          'URL tipica: http://192.168.1.69:${LanApiUrl.portaPadrao}',
        );
      }
      final repos = _criarReposTerminal(client);
      if (!mounted) return;
      setState(() {
        _apiClient = client;
        _produtoApi = repos.$1;
        _clienteApi = repos.$2;
        _vendaApi = repos.$3;
        _vendedorApi = repos.$4;
        _funcionarioApi = repos.$5;
        _motoristaApi = repos.$6;
        _contaPagarApi = repos.$7;
        _kitApi = repos.$8;
        _promoApi = repos.$9;
        _listaCompraApi = repos.$10;
        _usuarioApi = repos.$11;
        _nfeImportadaApi = repos.$12;
        _recadoLojaApi = repos.$13;
        _fornecedorApi = repos.$14;
        _terminalHidratando = false;
        _terminalPrecisaConfig = false;
        _terminalErro = null;
      });
      EntregaBaixaSyncService.instance.ligar(
        client: client,
        vendaApi: repos.$3,
        podLan: EntregaPodLanService(lanClient: client),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _terminalHidratando = false;
        _terminalErro = '$e';
        _terminalPrecisaConfig = true;
        _apiClient = null;
        _produtoApi = null;
        _clienteApi = null;
        _vendaApi = null;
        _vendedorApi = null;
        _funcionarioApi = null;
        _motoristaApi = null;
        _contaPagarApi = null;
        _kitApi = null;
        _promoApi = null;
        _listaCompraApi = null;
        _usuarioApi = null;
        _nfeImportadaApi = null;
        _recadoLojaApi = null;
        _fornecedorApi = null;
      });
      EntregaBaixaSyncService.instance.desligar();
    }
  }

  (
    ProdutoApiRepository,
    ClienteApiRepository,
    VendaApiRepository,
    VendedorApiRepository,
    FuncionarioApiRepository,
    MotoristaApiRepository,
    ContaPagarApiRepository,
    KitOrcamentoApiRepository,
    PromocaoApiRepository,
    ListaCompraApiRepository,
    UsuarioApiRepository,
    NfeImportadaApiRepository,
    RecadoLojaApiRepository,
    FornecedorApiRepository,
  ) _criarReposTerminal(LanApiClient client) {
    final produtoApi = ProdutoApiRepository(client);
    final clienteApi = ClienteApiRepository(client);
    final vendaApi = VendaApiRepository(client);
    final vendedorApi = VendedorApiRepository(client);
    final funcionarioApi = FuncionarioApiRepository(client);
    final motoristaApi = MotoristaApiRepository(client);
    final contaPagarApi = ContaPagarApiRepository(client);
    final kitApi = KitOrcamentoApiRepository(client);
    final promoApi = PromocaoApiRepository(client);
    final listaCompraApi = ListaCompraApiRepository(
      client,
      produtoRepository: produtoApi,
    );
    final usuarioApi = UsuarioApiRepository(client);
    final nfeImportadaApi = NfeImportadaApiRepository(client);
    final recadoLojaApi = RecadoLojaApiRepository(client);
    final fornecedorApi = FornecedorApiRepository(client);
    vendaApi.resolverCliente = clienteApi.obterPorId;
    vendaApi.resolverVendedor = vendedorApi.obterPorId;
    vendaApi.resolverProduto = produtoApi.obterPorId;
    return (
      produtoApi,
      clienteApi,
      vendaApi,
      vendedorApi,
      funcionarioApi,
      motoristaApi,
      contaPagarApi,
      kitApi,
      promoApi,
      listaCompraApi,
      usuarioApi,
      nfeImportadaApi,
      recadoLojaApi,
      fornecedorApi,
    );
  }

  /// Apos login: hidrata caches e liga WS/timers (nao roda na tela de login).
  Future<void> _hidratarTerminalPosLogin() async {
    final client = _apiClient;
    final produtoApi = _produtoApi;
    final clienteApi = _clienteApi;
    final vendaApi = _vendaApi;
    final vendedorApi = _vendedorApi;
    final funcionarioApi = _funcionarioApi;
    final motoristaApi = _motoristaApi;
    final contaPagarApi = _contaPagarApi;
    final kitApi = _kitApi;
    final promoApi = _promoApi;
    final listaCompraApi = _listaCompraApi;
    final recadoLojaApi = _recadoLojaApi;
    final fornecedorApi = _fornecedorApi;
    if (client == null ||
        produtoApi == null ||
        clienteApi == null ||
        vendaApi == null ||
        vendedorApi == null) {
      return;
    }
    if (produtoApi.hidratado) {
      LanApiEventHub.instance.sairStandby();
      if (LanApiEventHub.instance.client != client) {
        LanApiEventHub.instance.conectar(client, terminalLeve: true);
      }
      LanApiEventHub.instance.marcarOnline();
      LanApiEventHub.instance.removeListener(_onApiEvento);
      LanApiEventHub.instance.addListener(_onApiEvento);
      // Config empresa pode ter mudado no servidor desde o ultimo login.
      unawaited(_hidratarEmpresaConfigTerminal(client));
      unawaited(produtoApi.sincronizarSeDesatualizado());
      return;
    }

    if (!mounted) return;
    setState(() {
      _terminalCarregandoDados = true;
      _terminalHidratando = true;
    });
    try {
      LanApiEventHub.instance.conectar(client, terminalLeve: true);
      LanApiEventHub.instance.marcarOnline();
      await produtoApi.garantirCacheImagens();

      Future<void> opcional(String nome, Future<void> Function() f) async {
        try {
          await f();
        } catch (e) {
          debugPrint('Terminal leve: hidratar $nome ignorado: $e');
        }
      }

      await Future.wait([
        produtoApi.hidratar(),
        clienteApi.hidratar(),
        vendaApi.hidratarOrcamentos(),
        vendedorApi.hidratar(),
      ]);
      await Future.wait([
        opcional('titulos', () => vendaApi.hidratarTitulos()),
        opcional('pendenciasFiscais', () => vendaApi.hidratarPendenciasFiscais()),
        opcional('funcionarios', () => funcionarioApi?.hidratar() ?? Future.value()),
        opcional('motoristas', () => motoristaApi?.hidratar() ?? Future.value()),
        opcional('contasPagar', () => contaPagarApi?.hidratar() ?? Future.value()),
        opcional('kits', () => kitApi?.hidratar() ?? Future.value()),
        opcional('promocoes', () => promoApi?.hidratar() ?? Future.value()),
        opcional('listaCompra', () => listaCompraApi?.hidratar() ?? Future.value()),
        opcional('recados', () => recadoLojaApi?.hidratar() ?? Future.value()),
        opcional('fornecedores', () => fornecedorApi?.hidratar() ?? Future.value()),
        opcional('usuarios', () async {
          await _usuarioApi?.listarTodos(forcar: true);
        }),
        opcional('empresaConfig', () => _hidratarEmpresaConfigTerminal(client)),
      ]);
      LanApiEventHub.instance.addListener(_onApiEvento);
    } finally {
      if (mounted) {
        setState(() {
          _terminalHidratando = false;
          _terminalCarregandoDados = false;
        });
      }
    }
  }

  void _entrarStandbyTerminal() {
    _debounceEventoApi?.cancel();
    _debounceProdutoApi?.cancel();
    LanApiEventHub.instance.removeListener(_onApiEvento);
    LanApiEventHub.instance.entrarStandby();
    _produtoApi?.limparCache();
  }

  void _onApiEvento() {
    if (LanApiEventHub.instance.deveBloquearOperacoes) return;
    final ent = LanApiEventHub.instance.ultimaEntidade;
    if (ent.isEmpty) return;

    // Produto/estoque: fila propria — nao e cancelada por outros eventos (NF-e
    // dispara varias entidades em sequencia e antes atrasava o refresh).
    if (ent == 'produto' || ent == 'estoque' || ent == 'lote_produto') {
      final ids = LanApiEventHub.instance.ultimaEntidadeIds;
      if (ids.isNotEmpty) {
        final merged = <int>{..._produtoIdsApiPendentes, ...ids};
        _produtoIdsApiPendentes = merged.toList();
      }
      final rev = LanApiEventHub.instance.ultimaCatalogoRevision;
      if (rev > 0) _produtoRevisionPendente = rev;
      _debounceProdutoApi?.cancel();
      _debounceProdutoApi = Timer(const Duration(milliseconds: 50), () {
        if (!mounted || LanApiEventHub.instance.deveBloquearOperacoes) return;
        final produtoIds = List<int>.from(_produtoIdsApiPendentes);
        final revision = _produtoRevisionPendente;
        _produtoIdsApiPendentes = const [];
        _produtoRevisionPendente = null;
        unawaited(_atualizarCatalogoProdutoApi(
          ids: produtoIds,
          revision: revision,
        ));
      });
      if (ent == 'produto' || ent == 'estoque') {
        // Nao mistura com a fila generica.
        return;
      }
    }

    _entidadesApiPendentes.add(ent);
    _debounceEventoApi?.cancel();
    _debounceEventoApi = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || LanApiEventHub.instance.deveBloquearOperacoes) return;
      final pendentes = Set<String>.from(_entidadesApiPendentes);
      _entidadesApiPendentes.clear();
      pendentes.remove('produto');
      pendentes.remove('estoque');
      for (final e in pendentes) {
        _processarEventoApi(e);
      }
    });
  }

  Future<void> _atualizarCatalogoProdutoApi({
    List<int> ids = const [],
    int? revision,
  }) async {
    final repo = _produtoApi;
    if (repo == null) return;
    try {
      await repo.aplicarEventoRede(ids: ids, revision: revision);
    } on LanApiException {
      // Servidor caiu entre o evento e o HTTP.
    } catch (_) {}
  }

  void _processarEventoApi(
    String ent, {
    List<int>? produtoIdsOverride,
  }) {
    Future<void> safe(Future<void>? f) async {
      if (f == null) return;
      try {
        await f;
      } on LanApiException {
        // Servidor caiu entre o evento e o HTTP — nao propagar.
      } catch (_) {}
    }

    if (ent == 'venda') {
      unawaited(safe(_vendaApi?.hidratarOrcamentos()));
      unawaited(safe(_vendaApi?.hidratarEntregas(limit: 120)));
      unawaited(safe(_vendaApi?.hidratarPendenciasFiscais()));
    } else if (ent == 'nfe_saida') {
      // NfeGerenciamentoPage escuta o hub e recarrega o painel.
    } else if (ent == 'entrega') {
      unawaited(safe(_vendaApi?.hidratarEntregas(limit: 120)));
    } else if (ent == 'conferencia_carga') {
      // ConferenciaCargaConsolidadaLista escuta o hub e recarrega o escopo.
    } else if (ent == 'produto' || ent == 'estoque' || ent == 'lote_produto') {
      final ids = produtoIdsOverride ??
          LanApiEventHub.instance.ultimaEntidadeIds;
      unawaited(
        _atualizarCatalogoProdutoApi(
          ids: ids,
          revision: LanApiEventHub.instance.ultimaCatalogoRevision,
        ),
      );
    } else if (ent == 'cliente') {
      unawaited(safe(_clienteApi?.hidratar()));
    } else if (ent == 'fornecedor_nfe') {
      unawaited(safe(_fornecedorApi?.hidratar()));
    } else if (ent == 'conta_pagar' || ent == 'financeiro') {
      unawaited(safe(_contaPagarApi?.hidratar()));
    } else if (ent == 'funcionario' ||
        ent == 'lancamento_funcionario' ||
        ent == 'fechamento_rh_funcionario') {
      unawaited(safe(_funcionarioApi?.hidratar()));
    } else if (ent == 'kit_orcamento') {
      unawaited(safe(_kitApi?.hidratar()));
    } else if (ent == 'promocao') {
      unawaited(safe(_promoApi?.hidratar()));
    } else if (ent == 'motorista') {
      unawaited(safe(_motoristaApi?.hidratar()));
    } else if (ent == 'vendedor') {
      unawaited(safe(_vendedorApi?.hidratar()));
    } else if (ent == 'titulo_receber' || ent == 'recebimento_fiado') {
      unawaited(safe(_vendaApi?.hidratarTitulos()));
    } else if (ent == 'item_lista_compra') {
      unawaited(safe(_listaCompraApi?.hidratar()));
    } else if (ent == 'recado_loja') {
      unawaited(safe(_recadoLojaApi?.hidratar()));
    } else if (ent == 'nfe_importada') {
      // NfeImportadasPage escuta o hub e recarrega listagem/cards.
    } else if (ent == 'usuarios_sistema') {
      unawaited(safe(_usuarioApi?.listarTodos(forcar: true).then((_) {})));
    } else if (ent == 'empresa_config') {
      unawaited(safe(_hidratarEmpresaConfigTerminal(_apiClient)));
    }
  }

  Future<void> _hidratarEmpresaConfigTerminal(LanApiClient? client) async {
    if (client == null || !client.configurado) return;
    final m = await client.obterEmpresaConfig();
    final raw = m['config'];
    if (raw is! Map) return;
    final atual = await widget.appConfigRepository.carregarEmpresaConfig();
    final mesclado = SyncEntityCodecExtras.empresaConfigDeMap(
      atual,
      Map<String, dynamic>.from(raw),
    );
    await widget.appConfigRepository.salvarEmpresaConfig(
      mesclado,
      propagarRede: false,
    );
  }

  Future<void> _sair() async {
    final login = _usuarioLogado?.login ?? AuditoriaRegistrar.usuarioSessao;
    if (login.isNotEmpty) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.autenticacao,
        acao: AuditoriaAcao.logout,
        usuarioLogin: login,
        resumo: 'Logout: $login',
      );
    }
    AuditoriaRegistrar.limparUsuarioSessao();
    try {
      ChatInternoHub.instance.encerrarSessao();
    } catch (_) {}

    _debounceEventoApi?.cancel();
    _debounceProdutoApi?.cancel();
    LanApiEventHub.instance.removeListener(_onApiEvento);

    if (!mounted) return;
    setState(() {
      _usuarioLogado = null;
      // Terminal: mantem API/repos para novo login no mesmo servidor.
      if (!widget.terminalLeve) {
        _terminalPrecisaConfig = false;
        _terminalHidratando = false;
        _terminalErro = null;
        _apiClient = null;
        _produtoApi = null;
        _clienteApi = null;
        _vendaApi = null;
        _vendedorApi = null;
        _funcionarioApi = null;
        _motoristaApi = null;
        _contaPagarApi = null;
        _kitApi = null;
        _promoApi = null;
        _listaCompraApi = null;
        _usuarioApi = null;
        _nfeImportadaApi = null;
        _recadoLojaApi = null;
        _fornecedorApi = null;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.terminalLeve) {
        try {
          _entrarStandbyTerminal();
        } catch (_) {}
      } else {
        try {
          LanApiEventHub.instance.desconectar();
        } catch (_) {}
        unawaited(_posLogoutServidor());
      }
      unawaited(_carregarPersonalizacaoInicial());
    });
  }

  Future<void> _posLogoutServidor() async {
    try {
      await widget.lanSyncScheduler?.parar();
    } catch (_) {}
    try {
      await _executarBackupAoFechar(agendarHeadless: false);
    } catch (_) {}
  }

  Widget _buildTerminalRoot() {
    if (_terminalHidratando) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _terminalCarregandoDados
                    ? 'Carregando dados da loja...'
                    : 'Conectando ao PC servidor...',
              ),
            ],
          ),
        ),
      );
    }
    if (_terminalPrecisaConfig ||
        _usuarioApi == null ||
        _apiClient == null) {
      return TerminalConfigPage(
        appConfigRepository: widget.appConfigRepository,
        onLogout: () => unawaited(_sair()),
        onSalvo: _prepararTerminalLeve,
        erroConexao: _terminalErro,
      );
    }
    if (_usuarioLogado == null) {
      return LoginPage(
        usuarioRepository: _usuarioApi!,
        terminalRemoto: true,
        onLoginSuccess: _entrar,
      );
    }
    return MainAppShellPage(
      objectBox: null,
      terminalLeve: true,
      produtoRepository: _produtoApi!,
      clienteRepository: _clienteApi!,
      vendaRepository: _vendaApi!,
      vendedorRepository: _vendedorApi!,
      funcionarioRepository: _funcionarioApi!,
      motoristaRepository: _motoristaApi!,
      usuarioLogado: _usuarioLogado!,
      onLogout: () => unawaited(_sair()),
      lanSyncScheduler: null,
      appConfigRepository: widget.appConfigRepository,
      printService: _printService,
      vendaApiRepository: _vendaApi,
      lanApiClient: _apiClient,
      usuarioRepository: _usuarioApi,
      contaPagarRepository: _contaPagarApi,
      kitOrcamentoRepository: _kitApi,
      promocaoRepository: _promoApi,
      listaCompraRepository: _listaCompraApi,
      nfeImportadaRepository: _nfeImportadaApi,
      recadoLojaRepository: _recadoLojaApi,
      fornecedorRepository: _fornecedorApi,
    );
  }

  Widget _buildHomeLogado() {
    final produtoRepository = ProdutoRepository(widget.objectBox!);
    final vendaRepository = VendaRepository(
      widget.objectBox!,
      onAposEscrita: produtoRepository.atualizarCacheAposMovimentoEstoque,
    );
    return MainAppShellPage(
      objectBox: widget.objectBox!,
      terminalLeve: false,
      produtoRepository: produtoRepository,
      clienteRepository: ClienteRepository(widget.objectBox!),
      vendaRepository: vendaRepository,
      vendedorRepository: VendedorRepository(widget.objectBox!),
      funcionarioRepository: FuncionarioRepository(widget.objectBox!),
      motoristaRepository: MotoristaRepository(widget.objectBox!),
      usuarioLogado: _usuarioLogado!,
      onLogout: () => unawaited(_sair()),
      lanSyncScheduler: widget.lanSyncScheduler,
      appConfigRepository: widget.appConfigRepository,
      printService: _printService,
      usuarioRepository: _usuarioRepository,
      fornecedorRepository: FornecedorRepository(widget.objectBox!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temaData = AppThemeBuilder.build(_temaAtual);
    // Só o scaffold fica transparente para o plano de fundo aparecer.
    // NÃO zerar canvasColor: DropdownButton / menus usam isso e ficam ilegíveis.
    final temaComFundo = _fundoAtual.pintaCamada
        ? temaData.copyWith(scaffoldBackgroundColor: Colors.transparent)
        : temaData;
    return MaterialApp(
      key: const ValueKey<String>('sistema-vendas-app'),
      title: 'Sistema de Vendas',
      theme: temaComFundo,
      darkTheme: temaComFundo,
      themeMode: ThemeMode.light,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        return AppTemaScope(
          temaAtual: _temaAtual,
          definirTema: _definirTema,
          child: AppMenuModoScope(
            modoAtual: _menuModoAtual,
            definirModo: _definirMenuModo,
            child: AppFundoScope(
              fundoAtual: _fundoAtual,
              definirFundo: _definirFundo,
              child: Theme(
                data: temaComFundo,
                child: AppFundoCamada(
                  child: buildAdaptiveAppShell(context, child),
                ),
              ),
            ),
          ),
        );
      },
      home: widget.terminalLeve
          ? _buildTerminalRoot()
          : (_usuarioLogado == null
              ? LoginPage(
                  usuarioRepository: _usuarioRepository,
                  onLoginSuccess: _entrar,
                )
              : _buildHomeLogado()),
    );
  }
}

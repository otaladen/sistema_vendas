import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'domain/auditoria_catalogo.dart';
import 'data/app_config_repository.dart';
import 'data/app_menu_modo_repository.dart';
import 'data/app_tema_repository.dart';
import 'data/auditoria_repository.dart';
import 'data/auto_backup_service.dart';
import 'data/backup_agendado_headless_service.dart';
import 'data/backup_ao_fechar_service.dart';
import 'data/cadastro_duplicados_limpeza.dart';
import 'data/cliente_repository.dart';
import 'data/funcionario_repository.dart';
import 'data/motorista_repository.dart';
import 'data/objectbox.dart';
import 'data/produto_repository.dart';
import 'data/sync/lan_sync_scheduler.dart';
import 'data/sync/sync_primeira_carga.dart';
import 'data/sync/sync_service.dart';
import 'data/usuario_repository.dart';
import 'data/venda_repository.dart';
import 'data/vendedor_repository.dart';
import 'model/usuario_sistema.dart';
import 'services/auditoria_registrar.dart';
import 'services/auditoria_retencao_service.dart';
import 'services/print_service.dart';
import 'services/estoque_diagnostico_startup.dart';
import 'services/fiscal_config_store.dart';
import 'services/fiscal_reconciliacao_startup.dart';
import 'services/trusted_http_client.dart';
import 'ui/app_startup_error_page.dart';
import 'ui/layout/app_layout.dart';
import 'ui/login_page.dart';
import 'ui/main_menu_page.dart';
import 'ui/primeira_carga_page.dart';
import 'ui/theme/app_menu_modo_id.dart';
import 'ui/theme/app_menu_modo_scope.dart';
import 'ui/theme/app_tema_id.dart';
import 'ui/theme/app_tema_scope.dart';
import 'ui/theme/app_theme_builder.dart';

export 'ui/theme/app_semantic_colors.dart';

Future<void> main(List<String> args) async {
  if (BackupAgendadoHeadlessService.deveExecutar(args)) {
    final code = await BackupAgendadoHeadlessService.executar();
    exit(code);
  }

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      configurarHttpOverridesPlataforma();
      await initializeDateFormatting('pt_BR');
      await _tentarSincronizarHorarioSistemaNoInicio();

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
      final appConfigRepository = AppConfigRepository();
      await FiscalConfigStore.carregar();
      final empresaCfg = await appConfigRepository.carregarEmpresaConfig();
      await FiscalConfigStore.aplicarRegimeEmpresa(
        empresaCfg.regimeTributarioEmitente,
      );
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
      final syncService = SyncService(
        objectBox: objectBox,
        configRepository: appConfigRepository,
      );
      final lanSyncScheduler = LanSyncScheduler(syncService: syncService);
      runApp(
        MyApp(
          objectBox: objectBox,
          syncService: syncService,
          lanSyncScheduler: lanSyncScheduler,
          appConfigRepository: appConfigRepository,
        ),
      );
    },
    (error, stack) {
      debugPrint('Erro nao tratado: $error\n$stack');
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
  } catch (_) {
    // Falha silenciosa: sem permissao/rede/servico, app segue normalmente.
  }
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.objectBox,
    required this.syncService,
    required this.lanSyncScheduler,
    required this.appConfigRepository,
  });

  final ObjectBox objectBox;
  final SyncService syncService;
  final LanSyncScheduler lanSyncScheduler;
  final AppConfigRepository appConfigRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  UsuarioSistema? _usuarioLogado;
  AppTemaId _temaAtual = AppTemaId.verde;
  AppMenuModoId _menuModoAtual = AppMenuModoId.classico;
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  Timer? _timerBackupAutomatico;
  late final PrintService _printService;

  /// Apos login: bloqueia shell ate a carga inicial (banco vazio).
  bool _aguardandoPrimeiraCarga = false;
  bool _checandoPrimeiraCarga = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregarPersonalizacaoInicial());
    _printService = PrintService(widget.appConfigRepository);
    _timerBackupAutomatico = Timer.periodic(
      const Duration(minutes: 5),
      (_) => AutoBackupService.tentarExecutarSeDevido(
        widget.appConfigRepository,
        objectBox: widget.objectBox,
        lanSyncScheduler: widget.lanSyncScheduler,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AutoBackupService.tentarExecutarSeDevido(
        widget.appConfigRepository,
        objectBox: widget.objectBox,
        lanSyncScheduler: widget.lanSyncScheduler,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerBackupAutomatico?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LanSyncScheduler.aoRetomarApp();
    }
    if (state == AppLifecycleState.detached) {
      unawaited(_executarBackupAoFechar());
    }
  }

  Future<void> _executarBackupAoFechar() async {
    final nomeLoja = await _nomeLojaAtual();
    await BackupAoFecharService.tentarSeAtivo(
      repository: widget.appConfigRepository,
      objectBox: widget.objectBox,
      lanSyncScheduler: widget.lanSyncScheduler,
      nomeLoja: nomeLoja,
    );
  }

  Future<String> _nomeLojaAtual() async {
    final c = await widget.appConfigRepository.carregarEmpresaConfig();
    return c.nomeLoja;
  }

  Future<void> _carregarPersonalizacaoInicial() async {
    final results = await Future.wait([
      AppTemaRepository.carregar(),
      AppMenuModoRepository.carregar(),
    ]);
    if (!mounted) return;
    setState(() {
      _temaAtual = results[0] as AppTemaId;
      _menuModoAtual = results[1] as AppMenuModoId;
    });
  }

  Future<void> _definirTema(AppTemaId tema) async {
    // Aplica na hora — nao espera SharedPreferences (pode falhar/atrasar no Android).
    if (!mounted) return;
    setState(() => _temaAtual = tema);
    try {
      await AppTemaRepository.salvar(
        tema,
        login: _usuarioLogado?.login,
      );
    } catch (_) {}
  }

  Future<void> _definirMenuModo(AppMenuModoId modo) async {
    if (!mounted) return;
    setState(() => _menuModoAtual = modo);
    try {
      await AppMenuModoRepository.salvar(
        modo,
        login: _usuarioLogado?.login,
      );
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
    ]);
    if (!mounted) return;

    setState(() {
      _usuarioLogado = usuario;
      _temaAtual = personalizacao[0] as AppTemaId;
      _menuModoAtual = personalizacao[1] as AppMenuModoId;
      _checandoPrimeiraCarga = true;
      _aguardandoPrimeiraCarga = false;
    });

    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    final precisa = await SyncPrimeiraCarga.precisa(
      objectBox: widget.objectBox,
      redeSincronizacaoAtiva: config.redeSincronizacaoAtiva,
      redeModoServidor: config.redeModoServidor,
      redeServidorUrl: config.redeServidorUrl,
    );
    // Celular novo sem URL ainda: se o banco estiver vazio, obriga a tela
    // para o usuario informar o servidor (em vez de abrir o PDV vazio).
    final bancoVazio = await SyncPrimeiraCarga.precisaPorBanco(widget.objectBox);
    final forcarGateCliente = !config.redeModoServidor && bancoVazio;

    if (!mounted) return;
    setState(() {
      _checandoPrimeiraCarga = false;
      _aguardandoPrimeiraCarga = precisa || forcarGateCliente;
    });
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
    widget.lanSyncScheduler.parar();
    await _executarBackupAoFechar();
    final personalizacao = await Future.wait([
      AppTemaRepository.carregar(),
      AppMenuModoRepository.carregar(),
    ]);
    if (!mounted) return;
    setState(() {
      _usuarioLogado = null;
      _aguardandoPrimeiraCarga = false;
      _checandoPrimeiraCarga = false;
      _temaAtual = personalizacao[0] as AppTemaId;
      _menuModoAtual = personalizacao[1] as AppMenuModoId;
    });
  }

  void _concluirPrimeiraCarga() {
    if (!mounted) return;
    setState(() => _aguardandoPrimeiraCarga = false);
  }

  Widget _buildHomeLogado() {
    if (_checandoPrimeiraCarga) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_aguardandoPrimeiraCarga) {
      return PrimeiraCargaPage(
        objectBox: widget.objectBox,
        syncService: widget.syncService,
        appConfigRepository: widget.appConfigRepository,
        onConcluido: _concluirPrimeiraCarga,
        onLogout: () => unawaited(_sair()),
      );
    }

    final produtoRepository = ProdutoRepository(widget.objectBox);
    final vendaRepository = VendaRepository(
      widget.objectBox,
      onAposEscrita: produtoRepository.atualizarCacheAposMovimentoEstoque,
    );
    return MainAppShellPage(
      objectBox: widget.objectBox,
      produtoRepository: produtoRepository,
      clienteRepository: ClienteRepository(widget.objectBox),
      vendaRepository: vendaRepository,
      vendedorRepository: VendedorRepository(widget.objectBox),
      funcionarioRepository: FuncionarioRepository(widget.objectBox),
      motoristaRepository: MotoristaRepository(widget.objectBox),
      usuarioLogado: _usuarioLogado!,
      onLogout: () => unawaited(_sair()),
      lanSyncScheduler: widget.lanSyncScheduler,
      appConfigRepository: widget.appConfigRepository,
      printService: _printService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final temaData = AppThemeBuilder.build(_temaAtual);
    return MaterialApp(
      key: const ValueKey<String>('sistema-vendas-app'),
      title: 'Sistema de Vendas',
      theme: temaData,
      darkTheme: temaData,
      themeMode: ThemeMode.light,
      builder: (context, child) {
        return AppTemaScope(
          temaAtual: _temaAtual,
          definirTema: _definirTema,
          child: AppMenuModoScope(
            modoAtual: _menuModoAtual,
            definirModo: _definirMenuModo,
            child: Theme(
              data: temaData,
              child: buildAdaptiveAppShell(context, child),
            ),
          ),
        );
      },
      home: _usuarioLogado == null
          ? LoginPage(
              usuarioRepository: _usuarioRepository,
              onLoginSuccess: _entrar,
            )
          : _buildHomeLogado(),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'domain/auditoria_catalogo.dart';

import 'data/app_config_repository.dart';
import 'data/app_tema_repository.dart';
import 'data/auditoria_repository.dart';
import 'data/auto_backup_service.dart';
import 'data/backup_agendado_headless_service.dart';
import 'data/backup_ao_fechar_service.dart';
import 'data/cliente_repository.dart';
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
import 'services/print_service.dart';
import 'services/estoque_diagnostico_startup.dart';
import 'services/fiscal_config_store.dart';
import 'services/fiscal_reconciliacao_startup.dart';
import 'services/trusted_http_client.dart';
import 'ui/app_startup_error_page.dart';
import 'ui/layout/app_layout.dart';
import 'ui/login_page.dart';
import 'ui/main_menu_page.dart';
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
      final syncService = SyncService(
        objectBox: objectBox,
        configRepository: appConfigRepository,
      );
      final lanSyncScheduler = LanSyncScheduler(syncService: syncService);
      runApp(
        MyApp(
          objectBox: objectBox,
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
    required this.lanSyncScheduler,
    required this.appConfigRepository,
  });

  final ObjectBox objectBox;
  final LanSyncScheduler lanSyncScheduler;
  final AppConfigRepository appConfigRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  UsuarioSistema? _usuarioLogado;
  AppTemaId _temaAtual = AppTemaId.verde;
  final UsuarioRepository _usuarioRepository = UsuarioRepository();
  Timer? _timerBackupAutomatico;
  late final PrintService _printService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregarTemaInicial());
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

  Future<void> _carregarTemaInicial() async {
    final tema = await AppTemaRepository.carregar();
    if (!mounted) return;
    setState(() => _temaAtual = tema);
  }

  Future<void> _definirTema(AppTemaId tema) async {
    await AppTemaRepository.salvar(
      tema,
      login: _usuarioLogado?.login,
    );
    if (!mounted) return;
    setState(() => _temaAtual = tema);
  }

  Future<void> _entrar(UsuarioSistema usuario) async {
    AuditoriaRegistrar.definirUsuarioSessao(usuario.login);
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.autenticacao,
      acao: AuditoriaAcao.login,
      usuarioLogin: usuario.login,
      resumo: 'Login: ${usuario.nome} (${usuario.login})',
    );
    final temaUsuario =
        await AppTemaRepository.carregar(login: usuario.login);
    if (!mounted) return;
    setState(() {
      _usuarioLogado = usuario;
      _temaAtual = temaUsuario;
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
    final temaMaquina = await AppTemaRepository.carregar();
    if (!mounted) return;
    setState(() {
      _usuarioLogado = null;
      _temaAtual = temaMaquina;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppTemaScope(
      temaAtual: _temaAtual,
      definirTema: _definirTema,
      child: MaterialApp(
        title: 'Sistema de Vendas',
        builder: buildAdaptiveAppShell,
        theme: AppThemeBuilder.build(_temaAtual),
        home: _usuarioLogado == null
          ? LoginPage(
              usuarioRepository: _usuarioRepository,
              onLoginSuccess: _entrar,
            )
          : Builder(
              builder: (context) {
                final produtoRepository =
                    ProdutoRepository(widget.objectBox);
                final vendaRepository = VendaRepository(
                  widget.objectBox,
                  onAposEscrita: produtoRepository.invalidarCacheBusca,
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
              },
            ),
      ),
    );
  }
}

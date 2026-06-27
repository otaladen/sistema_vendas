import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/app_config_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/funcionario_repository.dart';
import '../../data/menu_favoritos_repository.dart';
import '../../data/motorista_repository.dart';
import '../../data/objectbox.dart';
import '../../data/produto_repository.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../../domain/backup_status_helper.dart';
import '../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../services/lan_sync_server_manager.dart';
import '../../services/print_service.dart';
import '../layout/app_layout.dart';
import '../main_menu_dashboard.dart';
import '../widgets/app_rodape_status_bar.dart';
import 'app_menu_lateral.dart';
import 'app_shell_scope.dart';
import 'main_menu_deps.dart';
import 'main_menu_router.dart';

/// Shell principal: rail lateral no desktop + favoritos por usuario.
class MainAppShellPage extends StatefulWidget {
  const MainAppShellPage({
    super.key,
    required this.objectBox,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.onLogout,
    required this.lanSyncScheduler,
    required this.appConfigRepository,
    required this.printService,
  });

  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler lanSyncScheduler;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;

  @override
  State<MainAppShellPage> createState() => _MainAppShellPageState();
}

class _MainAppShellPageState extends State<MainAppShellPage> {
  final _navKey = GlobalKey<NavigatorState>();
  MainMenuDestino _destino = MainMenuDestino.inicio;
  List<MainMenuDestino> _favoritos = const [];
  bool _railEstendido = true;
  bool _syncIniciado = false;
  int _fiscalPendencias = 0;
  bool _backupAlerta = false;
  Timer? _fiscalPendenciasTimer;

  @override
  void initState() {
    super.initState();
    _carregarFavoritos();
    unawaited(_atualizarBadgesMenu());
    _fiscalPendenciasTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_atualizarBadgesMenu()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarSyncSeNecessario();
    });
  }

  @override
  void dispose() {
    _fiscalPendenciasTimer?.cancel();
    super.dispose();
  }

  Future<void> _atualizarBadgesMenu() async {
    final fiscal = FiscalPendenciasResumoService.contar(
      vendaRepository: widget.vendaRepository,
    ).total;
    var backupAlerta = false;
    if (UsuarioPermissaoHelper.tem(
      widget.usuarioLogado,
      PermissaoUsuario.configuracoes,
    )) {
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      final manual =
          await widget.appConfigRepository.carregarRegistroBackupManual();
      backupAlerta = BackupStatusHelper.avaliar(
        config: config,
        manual: manual,
      ).exibirAlerta;
    }
    if (!mounted) return;
    if (fiscal == _fiscalPendencias && backupAlerta == _backupAlerta) return;
    setState(() {
      _fiscalPendencias = fiscal;
      _backupAlerta = backupAlerta;
    });
  }

  Future<void> _iniciarSyncSeNecessario() async {
    if (_syncIniciado) return;
    _syncIniciado = true;
    final config = await widget.appConfigRepository.carregarEmpresaConfig();
    if (Platform.isWindows &&
        config.redeModoServidor &&
        config.redeSincronizacaoAtiva) {
      await LanSyncServerManager.iniciarServidor(
        porta: config.redePortaServidor,
      );
    }
    await widget.lanSyncScheduler.iniciar();
  }

  Future<void> _carregarFavoritos() async {
    var favs =
        await MenuFavoritosRepository.carregar(widget.usuarioLogado.login);
    if (favs.isEmpty) {
      favs = MainMenuDestino.favoritosPadrao(widget.usuarioLogado);
      if (favs.isNotEmpty) {
        await MenuFavoritosRepository.salvar(widget.usuarioLogado.login, favs);
      }
    }
    if (!mounted) return;
    setState(() => _favoritos = favs);
  }

  Future<void> _alternarFavorito(MainMenuDestino destino) async {
    final atual = await MenuFavoritosRepository.alternar(
      login: widget.usuarioLogado.login,
      destino: destino,
      podeAcessar: destino.podeAcessar(widget.usuarioLogado),
    );
    if (!mounted) return;
    setState(() => _favoritos = atual);
  }

  void _irPara(MainMenuDestino destino) {
    if (!destino.podeAcessar(widget.usuarioLogado)) return;
    setState(() => _destino = destino);
    unawaited(_atualizarBadgesMenu());
    _navKey.currentState?.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: destino.name),
        builder: (_) => _conteudoDestino(destino),
      ),
      (_) => false,
    );
  }

  /// Valores para montar paginas sem depender do [BuildContext] do State
  /// (o InheritedWidget fica abaixo do State na arvore).
  MainMenuDeps _valoresDeps({Widget child = const SizedBox.shrink()}) {
    return MainMenuDeps(
      objectBox: widget.objectBox,
      produtoRepository: widget.produtoRepository,
      clienteRepository: widget.clienteRepository,
      vendaRepository: widget.vendaRepository,
      vendedorRepository: widget.vendedorRepository,
      funcionarioRepository: widget.funcionarioRepository,
      motoristaRepository: widget.motoristaRepository,
      usuarioLogado: widget.usuarioLogado,
      onLogout: widget.onLogout,
      lanSyncScheduler: widget.lanSyncScheduler,
      appConfigRepository: widget.appConfigRepository,
      printService: widget.printService,
      child: child,
    );
  }

  Widget _conteudoDestino(MainMenuDestino destino) {
    if (destino == MainMenuDestino.inicio) {
      return _valoresDeps(
        child: MainMenuDashboard(
          mostrarAppBar: true,
          onIniciarSync: _iniciarSyncSeNecessario,
        ),
      );
    }
    final deps = _valoresDeps();
    return _valoresDeps(
      child: MainMenuRouter.pagina(destino, deps),
    );
  }

  List<MainMenuDestino> get _itensRail => MainMenuDestino.itensRail(
        usuario: widget.usuarioLogado,
        favoritos: _favoritos,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!context.isDesktopLayout) {
          return _valoresDeps(
            child: MainMenuDashboard(
              onIniciarSync: _iniciarSyncSeNecessario,
            ),
          );
        }
        return AppShellScope(
          destinoAtual: _destino,
          favoritos: _favoritos,
          irPara: _irPara,
          alternarFavorito: _alternarFavorito,
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      AppMenuLateral(
                        itens: _itensRail,
                        destinoAtual: _destino,
                        onSelecionar: _irPara,
                        estendido: _railEstendido,
                        onAlternarEstendido: () =>
                            setState(() => _railEstendido = !_railEstendido),
                        badgeDe: _badgeRail,
                        quantidadeFavoritos: _favoritos.length,
                        larguraTela: constraints.maxWidth,
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        child: Navigator(
                          key: _navKey,
                          onGenerateRoute: (settings) {
                            return MaterialPageRoute<void>(
                              builder: (_) => _conteudoDestino(
                                MainMenuDestino.inicio,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                AppRodapeStatusBar(
                  usuarioLogin: widget.usuarioLogado.login,
                  usuarioNome: widget.usuarioLogado.nome,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _badgeRail(MainMenuDestino d) {
    if (d == MainMenuDestino.notasFiscais) return _fiscalPendencias;
    if (d == MainMenuDestino.configuracoes && _backupAlerta) return 1;
    return 0;
  }
}

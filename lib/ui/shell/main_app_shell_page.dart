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
import '../../domain/main_menu_destino.dart';
import '../../model/usuario_sistema.dart';
import '../../services/lan_sync_server_manager.dart';
import '../../services/print_service.dart';
import '../layout/app_layout.dart';
import '../main_menu_dashboard.dart';
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

  @override
  void initState() {
    super.initState();
    _carregarFavoritos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarSyncSeNecessario();
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

  int get _indiceRail {
    final idx = _itensRail.indexOf(_destino);
    return idx >= 0 ? idx : 0;
  }

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
            body: Row(
              children: [
                _rail(context),
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
        );
      },
    );
  }

  Widget _rail(BuildContext context) {
    final tema = Theme.of(context);
    final itens = _itensRail;
    final larguraEstendida = constraintsLargura(context) >= 1200;

    return NavigationRail(
      extended: _railEstendido && larguraEstendida,
      minExtendedWidth: 200,
      selectedIndex: _indiceRail.clamp(0, itens.length - 1),
      onDestinationSelected: (i) => _irPara(itens[i]),
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: IconButton(
          tooltip: _railEstendido ? 'Recolher menu' : 'Expandir menu',
          onPressed: () => setState(() => _railEstendido = !_railEstendido),
          icon: Icon(
            _railEstendido
                ? Icons.menu_open_rounded
                : Icons.menu_rounded,
          ),
        ),
      ),
      labelType: _railEstendido && larguraEstendida
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in itens)
          NavigationRailDestination(
            icon: Icon(d.icone),
            selectedIcon: Icon(d.icone, color: d.cor),
            label: Text(
              d.titulo,
              style: TextStyle(
                color: d == _destino ? d.cor : null,
                fontWeight: d == _destino ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_favoritos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_favoritos.length} fav.',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: tema.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            IconButton(
              tooltip: 'Inicio',
              onPressed: () => _irPara(MainMenuDestino.inicio),
              icon: const Icon(Icons.dashboard_outlined),
            ),
          ],
        ),
      ),
    );
  }

  double constraintsLargura(BuildContext context) =>
      MediaQuery.sizeOf(context).width;
}

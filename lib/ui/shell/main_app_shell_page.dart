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
import '../../domain/main_menu_sub_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../services/lan_sync_server_manager.dart';
import '../../services/print_service.dart';
import '../layout/app_layout.dart';
import '../main_menu_dashboard.dart';
import '../widgets/app_rodape_status_bar.dart';
import 'app_menu_lateral.dart';
import 'app_shell_aba_visibilidade.dart';
import 'app_shell_scope.dart';
import 'app_shell_tab.dart';
import 'app_shell_tab_bar.dart';
import 'app_shell_tab_navigator.dart';
import 'main_menu_deps.dart';
import 'main_menu_router.dart';
import 'main_menu_sub_router.dart';

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
  MainMenuDestino _destino = MainMenuDestino.inicio;
  MainMenuSubDestino? _subDestino;
  final Set<MainMenuDestino> _gruposExpandidos = {};
  List<MainMenuDestino> _favoritos = const [];
  bool _railEstendido = true;
  bool _syncIniciado = false;
  int _fiscalPendencias = 0;
  bool _backupAlerta = false;
  Timer? _fiscalPendenciasTimer;

  final List<AppShellTab> _abas = [];
  int _indiceAbaAtiva = 0;
  int _seqAba = 0;

  @override
  void initState() {
    super.initState();
    _abas.add(_criarAba(
      destino: MainMenuDestino.inicio,
      forcarNovaInstancia: true,
    ));
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
    final fiscal = UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
          widget.usuarioLogado,
        )
        ? FiscalPendenciasResumoService.contar(
            vendaRepository: widget.vendaRepository,
          ).total
        : 0;
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

  void _sincronizarGrupoExpandidoComDestino(MainMenuDestino destino) {
    if (MainMenuSubDestinoHelper.moduloTemSubmenu(destino)) {
      _gruposExpandidos
        ..clear()
        ..add(destino);
    } else {
      _gruposExpandidos.clear();
    }
  }

  void _irPara(MainMenuDestino destino, {String? configSecaoInicialId}) {
    if (!destino.podeAcessar(widget.usuarioLogado)) return;
    if (MainMenuSubDestinoHelper.moduloTemSubmenu(destino)) {
      final sub = MainMenuSubDestinoHelper.primeiroPermitido(
        destino,
        widget.usuarioLogado,
      );
      if (sub != null) {
        _irParaSub(destino, sub);
      }
      return;
    }
    if (destino == MainMenuDestino.configuracoes) {
      final secao = configSecaoInicialId ?? (_backupAlerta ? 'backup' : null);
      _abrirConfiguracoes(secaoInicialId: secao);
      return;
    }
    _abrirOuAtivarAba(destino: destino);
  }

  void _abrirConfiguracoes({String? secaoInicialId}) {
    const destino = MainMenuDestino.configuracoes;
    final id = AppShellTab.idDe(destino: destino);
    final idx = _abas.indexWhere((a) => a.id == id);

    if (idx >= 0 && secaoInicialId != null) {
      setState(() {
        _abas[idx] = _criarAba(
          destino: destino,
          configSecaoInicialId: secaoInicialId,
        );
        _ativarAba(idx, notificar: false);
      });
      unawaited(_atualizarBadgesMenu());
      return;
    }

    if (idx >= 0) {
      _ativarAba(idx);
      return;
    }

    setState(() {
      _abas.add(_criarAba(
        destino: destino,
        configSecaoInicialId: secaoInicialId,
      ));
      _ativarAba(_abas.length - 1, notificar: false);
    });
    unawaited(_atualizarBadgesMenu());
  }

  void _irParaSub(MainMenuDestino pai, MainMenuSubDestino sub) {
    if (!sub.podeAcessar(widget.usuarioLogado)) return;
    setState(() => _sincronizarGrupoExpandidoComDestino(pai));
    _abrirOuAtivarAba(destino: pai, sub: sub);
  }

  void _abrirOuAtivarAba({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    bool forcarNovaInstancia = false,
  }) {
    final id = forcarNovaInstancia
        ? 'inst:${_seqAba++}'
        : AppShellTab.idDe(destino: destino, sub: sub);

    if (!forcarNovaInstancia) {
      final existente = _abas.indexWhere((a) => a.id == id);
      if (existente >= 0) {
        _ativarAba(existente);
        return;
      }
    }

    setState(() {
      _abas.add(_criarAba(
        destino: destino,
        sub: sub,
        id: id,
      ));
      _ativarAba(_abas.length - 1, notificar: false);
    });
    unawaited(_atualizarBadgesMenu());
  }

  AppShellTab _criarAba({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    String? id,
    bool forcarNovaInstancia = false,
    String? configSecaoInicialId,
  }) {
    final tabId = id ??
        (forcarNovaInstancia
            ? 'inst:${_seqAba++}'
            : AppShellTab.idDe(destino: destino, sub: sub));
    return AppShellTab(
      id: tabId,
      titulo: AppShellTab.tituloDe(destino: destino, sub: sub),
      destino: destino,
      subDestino: sub,
      navigatorKey: GlobalKey<NavigatorState>(),
      paginaInicial: _conteudoAba(
        destino: destino,
        sub: sub,
        configSecaoInicialId: configSecaoInicialId,
      ),
    );
  }

  void _ativarAba(int indice, {bool notificar = true}) {
    if (indice < 0 || indice >= _abas.length) return;
    final aba = _abas[indice];
    void aplicar() {
      _indiceAbaAtiva = indice;
      _destino = aba.destino;
      _subDestino = aba.subDestino;
      _sincronizarGrupoExpandidoComDestino(aba.destino);
    }

    if (notificar) {
      setState(aplicar);
      unawaited(_atualizarBadgesMenu());
    } else {
      aplicar();
    }
  }

  void _selecionarAba(int indice) => _ativarAba(indice);

  void _fecharAba(int indice) {
    if (_abas.length <= 1) return;
    setState(() {
      _abas.removeAt(indice);
      if (_indiceAbaAtiva >= _abas.length) {
        _indiceAbaAtiva = _abas.length - 1;
      } else if (indice < _indiceAbaAtiva) {
        _indiceAbaAtiva--;
      }
      final aba = _abas[_indiceAbaAtiva];
      _destino = aba.destino;
      _subDestino = aba.subDestino;
      _sincronizarGrupoExpandidoComDestino(aba.destino);
    });
  }

  void _fecharAbaAtual() => _fecharAba(_indiceAbaAtiva);

  Widget _conteudoAba({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    String? configSecaoInicialId,
  }) {
    if (sub != null) {
      final deps = _valoresDeps();
      return _valoresDeps(
        child: Builder(
          builder: (ctx) => MainMenuSubRouter.pagina(
            sub,
            deps,
            navigatorContext: ctx,
          ),
        ),
      );
    }
    return _conteudoDestino(
      destino,
      configSecaoInicialId: configSecaoInicialId,
    );
  }

  void _alternarGrupoMenu(MainMenuDestino grupo) {
    setState(() {
      if (_gruposExpandidos.contains(grupo)) {
        _gruposExpandidos.remove(grupo);
      } else {
        _gruposExpandidos
          ..clear()
          ..add(grupo);
      }
    });
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

  Widget _conteudoDestino(
    MainMenuDestino destino, {
    String? configSecaoInicialId,
  }) {
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
      child: MainMenuRouter.pagina(
        destino,
        deps,
        configSecaoInicialId: configSecaoInicialId,
      ),
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
          subDestinoAtual: _subDestino,
          favoritos: _favoritos,
          irPara: _irPara,
          irParaSub: _irParaSub,
          alternarFavorito: _alternarFavorito,
          fecharAbaAtual: _fecharAbaAtual,
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      AppMenuLateral(
                        itens: _itensRail,
                        destinoAtual: _destino,
                        subDestinoAtual: _subDestino,
                        usuarioLogado: widget.usuarioLogado,
                        onSelecionar: _irPara,
                        onSelecionarSub: _irParaSub,
                        gruposExpandidos: _gruposExpandidos,
                        onAlternarGrupo: _alternarGrupoMenu,
                        estendido: _railEstendido,
                        onAlternarEstendido: () =>
                            setState(() => _railEstendido = !_railEstendido),
                        badgeDe: _badgeRail,
                        badgeSubDe: _badgeSub,
                        quantidadeFavoritos: _favoritos.length,
                        larguraTela: constraints.maxWidth,
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppShellTabBar(
                              tabs: _abas,
                              indiceAtivo: _indiceAbaAtiva,
                              onSelecionar: _selecionarAba,
                              onFecharAtiva: _fecharAbaAtual,
                            ),
                            Expanded(
                              child: IndexedStack(
                                index: _indiceAbaAtiva,
                                children: [
                                  for (var i = 0; i < _abas.length; i++)
                                    AppShellAbaVisibilidade(
                                      ativa: i == _indiceAbaAtiva,
                                      child: AppShellTabNavigator(
                                        key: ValueKey<String>(_abas[i].id),
                                        navigatorKey: _abas[i].navigatorKey,
                                        paginaInicial: _abas[i].paginaInicial,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
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
    if (d == MainMenuDestino.notasFiscais &&
        UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
          widget.usuarioLogado,
        )) {
      return _fiscalPendencias;
    }
    if (d == MainMenuDestino.configuracoes && _backupAlerta) return 1;
    return 0;
  }

  int _badgeSub(MainMenuSubDestino sub) {
    if (sub == MainMenuSubDestino.fiscalPendencias &&
        UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
          widget.usuarioLogado,
        )) {
      return _fiscalPendencias;
    }
    return 0;
  }
}

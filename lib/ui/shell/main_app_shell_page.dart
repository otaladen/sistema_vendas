import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/configuracoes_service.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/venda_api_repository.dart';
import '../../data/menu_favoritos_repository.dart';
import '../../data/objectbox.dart';
import '../../data/sync/lan_sync_scheduler.dart';
import '../../data/venda_repository.dart';
import '../../domain/backup_status_helper.dart';
import '../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../domain/modo_terminal_leve.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../../services/lan_servidor_bootstrap.dart';
import '../../services/print_service.dart';
import '../layout/app_layout.dart';
import '../listagem_vendas_page.dart';
import '../main_menu_dashboard.dart';
import '../theme/app_fundo_camada.dart';
import '../widgets/app_rodape_status_bar.dart';
import '../widgets/chat/chat_interno_drawer.dart';
import '../widgets/chat/chat_interno_hub.dart';
import '../../data/api/chat_api_repository.dart';
import '../../data/mensagem_interna_repository.dart';
import '../../data/usuario_repository.dart';
import 'app_menu_drawer.dart';
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
    this.terminalLeve = false,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.onLogout,
    required this.lanSyncScheduler,
    required this.configuracoesService,
    required this.printService,
    this.vendaApiRepository,
    this.lanApiClient,
    this.usuarioRepository,
    this.contaPagarRepository,
    this.kitOrcamentoRepository,
    this.promocaoRepository,
    this.listaCompraRepository,
    this.nfeImportadaRepository,
    this.recadoLojaRepository,
    this.fornecedorRepository,
  });

  final ObjectBox? objectBox;
  final bool terminalLeve;
  final dynamic produtoRepository;
  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final dynamic funcionarioRepository;
  final dynamic motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler? lanSyncScheduler;
  final ConfiguracoesService configuracoesService;
  final PrintService printService;
  final dynamic vendaApiRepository;
  final LanApiClient? lanApiClient;
  final dynamic usuarioRepository;
  final dynamic contaPagarRepository;
  final dynamic kitOrcamentoRepository;
  final dynamic promocaoRepository;
  final dynamic listaCompraRepository;
  final dynamic nfeImportadaRepository;
  final dynamic recadoLojaRepository;
  final dynamic fornecedorRepository;

  @override
  State<MainAppShellPage> createState() => _MainAppShellPageState();
}

class _MainAppShellPageState extends State<MainAppShellPage> {
  late MainMenuDestino _destino;
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

  /// Shell mobile: gaveta + navigator (sem abas desktop).
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();
  Widget? _paginaModuloMobile;

  @override
  void initState() {
    super.initState();
    final inicial = MainMenuDestino.inicialAposLogin(widget.usuarioLogado);
    _destino = inicial;
    // Singleton: id estavel dest:inicio (evita aba duplicada ao clicar Inicio).
    _abas.add(_criarAba(destino: inicial));
    if (inicial != MainMenuDestino.inicio) {
      _paginaModuloMobile = _conteudoAba(destino: inicial);
    }
    _carregarFavoritos();
    // Badge fiscal no celular: nao na entrada (congela). So no timer de 60s+.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      unawaited(_atualizarBadgesMenu());
    }
    _fiscalPendenciasTimer = Timer.periodic(
      const Duration(seconds: 120),
      (_) => unawaited(_atualizarBadgesMenu()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarSyncSeNecessario();
      _configurarChatInterno();
    });
  }

  void _configurarChatInterno() {
    final autor = widget.usuarioLogado.nome.trim().isNotEmpty
        ? widget.usuarioLogado.nome.trim()
        : widget.usuarioLogado.login;
    ChatInternoHub.instance.configurar(
      localRepo: widget.objectBox != null
          ? MensagemInternaRepository(
              storeDirectoryPath: widget.objectBox!.storeDirectoryPath,
            )
          : null,
      apiRepo: widget.lanApiClient != null
          ? ChatApiRepository(widget.lanApiClient!)
          : null,
      autorPadrao: autor,
      perfilUsuario: widget.usuarioLogado.perfil,
      loginUsuario: widget.usuarioLogado.login,
      usuarioLogado: widget.usuarioLogado,
      usuarioRepo: widget.usuarioRepository is UsuarioRepository
          ? widget.usuarioRepository as UsuarioRepository
          : (widget.terminalLeve ? null : UsuarioRepository()),
    );
  }

  @override
  void dispose() {
    _fiscalPendenciasTimer?.cancel();
    super.dispose();
  }

  Future<void> _atualizarBadgesMenu() async {
    if (widget.terminalLeve) {
      var fiscal = 0;
      if (UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
        widget.usuarioLogado,
      )) {
        final api = widget.vendaApiRepository is VendaApiRepository
            ? widget.vendaApiRepository as VendaApiRepository
            : (widget.vendaRepository is VendaApiRepository
                ? widget.vendaRepository as VendaApiRepository
                : null);
        if (api != null) {
          try {
            await api.hidratarPendenciasFiscais();
            fiscal = api.metaPendenciasFiscaisTotal;
          } catch (_) {
            fiscal = api.metaPendenciasFiscaisTotal;
          }
        }
      }
      if (!mounted) return;
      if (fiscal == _fiscalPendencias && !_backupAlerta) return;
      setState(() {
        _fiscalPendencias = fiscal;
        _backupAlerta = false;
      });
      return;
    }
    final fiscal = UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
              widget.usuarioLogado,
            ) &&
            widget.vendaRepository is VendaRepository
        ? FiscalPendenciasResumoService.contar(
            vendaRepository: widget.vendaRepository as VendaRepository,
          ).total
        : 0;
    var backupAlerta = false;
    if (UsuarioPermissaoHelper.tem(
      widget.usuarioLogado,
      PermissaoUsuario.configuracoes,
    )) {
      final config = await widget.configuracoesService.carregarEfetiva();
      final manual =
          await widget.configuracoesService.repository.carregarRegistroBackupManual();
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
    if (widget.terminalLeve) return;

    final config = await widget.configuracoesService.carregarEfetiva();
    if (Platform.isWindows &&
        config.redeModoServidor &&
        config.redeSincronizacaoAtiva &&
        widget.objectBox != null) {
      // PC1: LanApi :8788. Sem scheduler P2P.
      await LanServidorBootstrap.garantirAtivo(
        objectBox: widget.objectBox!,
        configRepository: widget.configuracoesService.repository,
      );
      return;
    }

    // Celular / cliente legado: pull/push do hub.
    await widget.lanSyncScheduler?.iniciar();
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
    if (widget.terminalLeve && !destinoPermitidoNoTerminalLeve(destino.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modulo disponivel apenas no PC servidor (terminal leve).',
          ),
        ),
      );
      return;
    }
    if (!destino.podeAcessar(widget.usuarioLogado)) return;
    if (MainMenuSubDestinoHelper.moduloTemSubmenu(destino)) {
      final sub = MainMenuSubDestinoHelper.primeiroPermitido(
        destino,
        widget.usuarioLogado,
        terminalLeve: widget.terminalLeve,
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

    if (!_podeAbrirNovaAba()) return;

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

  /// Modulos gerais: uma aba por destino/sub (singleton). Reclique foca a existente.
  void _abrirOuAtivarAba({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
  }) {
    final id = AppShellTab.idDe(destino: destino, sub: sub);
    final existente = _abas.indexWhere((a) => a.id == id);
    if (existente >= 0) {
      // KPI "Vendas hoje": recria a listagem com periodo "hoje".
      if (sub == MainMenuSubDestino.vendasListagem &&
          ListagemVendasAbertura.temPeriodoPendente) {
        setState(() {
          _abas[existente] = _criarAba(destino: destino, sub: sub, id: id);
          _ativarAba(existente, notificar: false);
        });
        unawaited(_atualizarBadgesMenu());
        return;
      }
      _ativarAba(existente);
      return;
    }
    if (!_podeAbrirNovaAba()) return;

    setState(() {
      _abas.add(_criarAba(destino: destino, sub: sub, id: id));
      _ativarAba(_abas.length - 1, notificar: false);
    });
    unawaited(_atualizarBadgesMenu());
  }

  /// Documentos/orcamentos: varias abas com IDs distintos (`doc:tipo:id`).
  void _abrirAbaDocumento({
    required String tipo,
    required Object documentoId,
    required String titulo,
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    required Widget pagina,
  }) {
    final id = AppShellTab.idDocumento(tipo: tipo, documentoId: documentoId);
    final existente = _abas.indexWhere((a) => a.id == id);
    if (existente >= 0) {
      _ativarAba(existente);
      return;
    }
    if (!_podeAbrirNovaAba()) return;

    setState(() {
      _abas.add(
        AppShellTab(
          id: id,
          titulo: titulo,
          destino: destino,
          subDestino: sub,
          ehDocumento: true,
          navigatorKey: GlobalKey<NavigatorState>(),
          paginaInicial: pagina,
        ),
      );
      _ativarAba(_abas.length - 1, notificar: false);
    });
    unawaited(_atualizarBadgesMenu());
  }

  /// Mobile: abre documento como modulo unico (sem multi-aba).
  void _abrirAbaDocumentoMobile({
    required String tipo,
    required Object documentoId,
    required String titulo,
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    required Widget pagina,
  }) {
    _fecharDrawerMobile();
    setState(() {
      _destino = destino;
      _subDestino = sub;
      _paginaModuloMobile = pagina;
    });
    unawaited(_atualizarBadgesMenu());
  }

  bool _podeAbrirNovaAba() {
    if (_abas.length < AppShellTab.maxAbasAbertas) return true;
    _avisarLimiteAbas();
    return false;
  }

  void _avisarLimiteAbas() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Limite de ${AppShellTab.maxAbasAbertas} abas atingido. '
          'Feche alguma aba para abrir outra.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  AppShellTab _criarAba({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    String? id,
    String? configSecaoInicialId,
  }) {
    return AppShellTab(
      id: id ?? AppShellTab.idDe(destino: destino, sub: sub),
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

  void _proximaAba() {
    if (_abas.length <= 1) return;
    _ativarAba((_indiceAbaAtiva + 1) % _abas.length);
  }

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

  void _fecharOutras(int manter) {
    if (_abas.length <= 1) return;
    if (manter < 0 || manter >= _abas.length) return;
    setState(() {
      final keep = _abas[manter];
      _abas
        ..clear()
        ..add(keep);
      _indiceAbaAtiva = 0;
      _destino = keep.destino;
      _subDestino = keep.subDestino;
      _sincronizarGrupoExpandidoComDestino(keep.destino);
    });
  }

  void _fecharTodas() {
    if (_abas.length <= 1) {
      final unica = _abas.isEmpty
          ? null
          : _abas.first;
      if (unica != null &&
          unica.id == AppShellTab.idDe(destino: MainMenuDestino.inicio)) {
        return;
      }
    }
    setState(() {
      final inicioId = AppShellTab.idDe(destino: MainMenuDestino.inicio);
      final idx = _abas.indexWhere((a) => a.id == inicioId);
      final inicio =
          idx >= 0 ? _abas[idx] : _criarAba(destino: MainMenuDestino.inicio);
      _abas
        ..clear()
        ..add(inicio);
      _indiceAbaAtiva = 0;
      _destino = MainMenuDestino.inicio;
      _subDestino = null;
      _sincronizarGrupoExpandidoComDestino(MainMenuDestino.inicio);
    });
  }

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
      terminalLeve: widget.terminalLeve,
      produtoRepository: widget.produtoRepository,
      clienteRepository: widget.clienteRepository,
      vendaRepository: widget.vendaRepository,
      vendedorRepository: widget.vendedorRepository,
      funcionarioRepository: widget.funcionarioRepository,
      motoristaRepository: widget.motoristaRepository,
      usuarioLogado: widget.usuarioLogado,
      onLogout: widget.onLogout,
      lanSyncScheduler: widget.lanSyncScheduler,
      configuracoesService: widget.configuracoesService,
      printService: widget.printService,
      vendaApiRepository: widget.vendaApiRepository is VendaApiRepository
          ? widget.vendaApiRepository as VendaApiRepository
          : null,
      lanApiClient: widget.lanApiClient,
      usuarioRepository: widget.usuarioRepository,
      contaPagarRepository: widget.contaPagarRepository,
      kitOrcamentoRepository: widget.kitOrcamentoRepository,
      promocaoRepository: widget.promocaoRepository,
      listaCompraRepository: widget.listaCompraRepository,
      nfeImportadaRepository: widget.nfeImportadaRepository,
      recadoLojaRepository: widget.recadoLojaRepository,
      fornecedorRepository: widget.fornecedorRepository,
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

  List<MainMenuDestino> get _itensRail {
    final base = MainMenuDestino.itensRail(
      usuario: widget.usuarioLogado,
      favoritos: _favoritos,
    );
    if (!widget.terminalLeve) return base;
    return base
        .where((d) => destinoPermitidoNoTerminalLeve(d.name))
        .toList();
  }

  void _fecharDrawerMobile() {
    final state = _mobileScaffoldKey.currentState;
    if (state?.isDrawerOpen ?? false) {
      state!.closeDrawer();
    }
  }

  void _irParaMobile(MainMenuDestino destino, {String? configSecaoInicialId}) {
    if (widget.terminalLeve && !destinoPermitidoNoTerminalLeve(destino.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modulo disponivel apenas no PC servidor (terminal leve).',
          ),
        ),
      );
      return;
    }
    if (!destino.podeAcessar(widget.usuarioLogado)) return;
    if (MainMenuSubDestinoHelper.moduloTemSubmenu(destino)) {
      final sub = MainMenuSubDestinoHelper.primeiroPermitido(
        destino,
        widget.usuarioLogado,
        terminalLeve: widget.terminalLeve,
      );
      if (sub != null) {
        _irParaSubMobile(destino, sub);
      }
      return;
    }
    _fecharDrawerMobile();
    if (destino == MainMenuDestino.inicio) {
      setState(() {
        _destino = MainMenuDestino.inicio;
        _subDestino = null;
        _paginaModuloMobile = null;
      });
      return;
    }
    setState(() {
      _destino = destino;
      _subDestino = null;
      _paginaModuloMobile = _conteudoAba(
        destino: destino,
        configSecaoInicialId: destino == MainMenuDestino.configuracoes
            ? (configSecaoInicialId ?? (_backupAlerta ? 'backup' : null))
            : configSecaoInicialId,
      );
    });
    unawaited(_atualizarBadgesMenu());
  }

  void _irParaSubMobile(MainMenuDestino pai, MainMenuSubDestino sub) {
    if (!sub.podeAcessar(widget.usuarioLogado)) return;
    _fecharDrawerMobile();
    setState(() {
      _destino = pai;
      _subDestino = sub;
      _sincronizarGrupoExpandidoComDestino(pai);
      _paginaModuloMobile = _conteudoAba(destino: pai, sub: sub);
    });
    unawaited(_atualizarBadgesMenu());
  }

  void _fecharModuloMobile() {
    setState(() {
      _destino = MainMenuDestino.inicio;
      _subDestino = null;
      _paginaModuloMobile = null;
    });
  }

  Widget _buildShellMobile(BuildContext context) {
    return AppShellScope(
      destinoAtual: _destino,
      subDestinoAtual: _subDestino,
      favoritos: _favoritos,
      irPara: _irParaMobile,
      irParaSub: _irParaSubMobile,
      alternarFavorito: _alternarFavorito,
      fecharAbaAtual: _fecharModuloMobile,
      abrirAbaDocumento: _abrirAbaDocumentoMobile,
      child: Scaffold(
        key: _mobileScaffoldKey,
        drawer: AppMenuDrawer(
          itens: _itensRail,
          destinoAtual: _destino,
          subDestinoAtual: _subDestino,
          usuarioLogado: widget.usuarioLogado,
          onSelecionar: _irParaMobile,
          onSelecionarSub: _irParaSubMobile,
          badgeDe: _badgeRail,
          badgeSubDe: _badgeSub,
          terminalLeve: widget.terminalLeve,
        ),
        body: AppFundoCamada(
          child: Navigator(
          pages: [
            MaterialPage<void>(
              key: const ValueKey<String>('mobile-inicio'),
              child: MainMenuDashboard(
                onIniciarSync: _iniciarSyncSeNecessario,
                onAbrirMenu: () =>
                    _mobileScaffoldKey.currentState?.openDrawer(),
              ),
            ),
            if (_paginaModuloMobile != null)
              MaterialPage<void>(
                key: ValueKey<String>(
                  'mobile-${_destino.name}-${_subDestino?.name ?? 'root'}',
                ),
                child: Scaffold(
                  floatingActionButton: FloatingActionButton.small(
                    heroTag: 'menu_modulos_mobile',
                    tooltip: 'Abrir menu',
                    onPressed: () =>
                        _mobileScaffoldKey.currentState?.openDrawer(),
                    child: const Icon(Icons.menu_rounded),
                  ),
                  floatingActionButtonLocation:
                      FloatingActionButtonLocation.startFloat,
                  body: _paginaModuloMobile!,
                ),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key == const ValueKey<String>('mobile-inicio')) {
              return;
            }
            _fecharModuloMobile();
          },
        ),
        ),
        bottomNavigationBar: AppRodapeStatusBar(
          usuarioLogin: widget.usuarioLogado.login,
          usuarioNome: widget.usuarioLogado.nome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!context.isDesktopLayout) {
          return _valoresDeps(child: _buildShellMobile(context));
        }
        return _valoresDeps(
          child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                _fecharAbaAtual,
            const SingleActivator(LogicalKeyboardKey.tab, control: true):
                _proximaAba,
          },
          child: Focus(
            autofocus: true,
            child: AppShellScope(
              destinoAtual: _destino,
              subDestinoAtual: _subDestino,
              favoritos: _favoritos,
              irPara: _irPara,
              irParaSub: _irParaSub,
              alternarFavorito: _alternarFavorito,
              fecharAbaAtual: _fecharAbaAtual,
              abrirAbaDocumento: _abrirAbaDocumento,
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
                            terminalLeve: widget.terminalLeve,
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
                                  onFechar: _fecharAba,
                                  onFecharOutras: _fecharOutras,
                                  onFecharTodas: _fecharTodas,
                                  trailing: const ChatInternoTopBarButton(),
                                ),
                                Expanded(
                                  child: AppFundoCamada(
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
            ),
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

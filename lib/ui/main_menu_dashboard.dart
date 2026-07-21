import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../data/menu_favoritos_repository.dart';
import '../../data/recado_loja_repository.dart';
import '../../data/sync/sync_log.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../domain/backup_status_helper.dart';
import '../../domain/dashboard_alertas.dart';
import '../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/recado_loja.dart';
import '../../services/alertas_proativos_service.dart';
import '../../services/lan_sync_server_manager.dart';
import 'loja_ao_vivo_page.dart';
import 'layout/app_layout.dart';
import 'shell/app_shell_aba_visibilidade.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';
import 'widgets/seletor_tema_app.dart';
import 'recados_loja_page.dart';
import 'widgets/recados_loja_faixa.dart';
import 'widgets/dashboard_alertas_strip.dart';
import 'widgets/app_rodape_status_bar.dart';
import 'widgets/main_menu_widgets.dart';
import 'shell/app_shell_scope.dart';
import 'shell/main_menu_deps.dart';
import 'shell/main_menu_router.dart';

class _MainMenuResumo {
  const _MainMenuResumo({
    required this.vendasHoje,
    required this.faturamentoHoje,
    required this.caixaAberto,
    required this.entregasEmAberto,
    required this.entregasAtrasadas,
    required this.alertas,
    this.totalAReceber,
    this.totalFiadoVencido,
    this.fiscalPendencias = 0,
    this.backupAlerta = false,
  });

  final int vendasHoje;
  final double faturamentoHoje;
  final bool caixaAberto;
  final int entregasEmAberto;
  final int entregasAtrasadas;
  final List<DashboardAlerta> alertas;
  final double? totalAReceber;
  final double? totalFiadoVencido;
  final int fiscalPendencias;
  final bool backupAlerta;
}

/// Painel inicial (KPIs + modulos). Usado no mobile e no shell desktop.
class MainMenuDashboard extends StatefulWidget {
  const MainMenuDashboard({
    super.key,
    this.mostrarAppBar = true,
    this.onIniciarSync,
    this.onAbrirMenu,
  });

  final bool mostrarAppBar;
  final Future<void> Function()? onIniciarSync;

  /// Abre a gaveta do shell mobile (ícone ☰).
  final VoidCallback? onAbrirMenu;

  @override
  State<MainMenuDashboard> createState() => _MainMenuDashboardState();
}

class _MainMenuDashboardState extends State<MainMenuDashboard> {
  static final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _dataHora = DateFormat('EEEE, d MMMM yyyy · HH:mm', 'pt_BR');

  EmpresaConfig? _config;
  _MainMenuResumo? _resumo;
  bool _carregandoResumo = true;
  String _dataHoraExibida = '';
  Timer? _relogioTimer;
  Timer? _alertasProativosTimer;
  AlertasProativosService? _alertasProativosService;
  List<MainMenuDestino> _favoritos = const [];
  List<RecadoLoja> _recadosNaoLidos = const [];
  Timer? _fiscalPendenciasTimer;
  bool _timersPeriodicosAtivos = false;
  VoidCallback? _syncHubListener;

  @override
  void initState() {
    super.initState();
    _syncHubListener = () {
      if (!mounted) return;
      // Celular: sync nao deve forcar rebuild do painel (ANR).
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return;
      unawaited(_carregarPainel());
    };
    SyncRefreshHub.instance.addListener(_syncHubListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) => _inicializar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sincronizarTimersComVisibilidade();
  }

  Future<void> _inicializar() async {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;

    // KPIs locais primeiro — nunca esperar a sync de rede (no celular o bootstrap
    // pode demorar e deixava os cards girando para sempre).
    await _carregarFavoritos();
    await _carregarPainel();
    if (mounted) _sincronizarTimersComVisibilidade();

    unawaited(_iniciarSyncEmSegundoPlano(deps));
  }

  Future<void> _iniciarSyncEmSegundoPlano(MainMenuDeps deps) async {
    try {
      if (widget.onIniciarSync != null) {
        await widget.onIniciarSync!();
      } else {
        final config = await deps.appConfigRepository.carregarEmpresaConfig();
        if (Platform.isWindows &&
            config.redeModoServidor &&
            config.redeSincronizacaoAtiva) {
          await LanSyncServerManager.iniciarServidor(
            porta: config.redePortaServidor,
            syncToken: config.redeSyncToken,
            productImagesPath: deps.produtoRepository.productImagesDirPath,
          );
        }
        await deps.lanSyncScheduler.iniciar();
        if (Platform.isWindows &&
            config.redeModoServidor &&
            config.redeSincronizacaoAtiva) {
          unawaited(deps.lanSyncScheduler.enviarFotosProdutosAgora());
        }
      }
    } catch (_) {
      // Sync falhou: painel ja foi carregado com dados locais.
    }
    // No celular nao recarrega o painel de novo (trabalho pesado); no PC atualiza.
    if (mounted &&
        (kIsWeb || !(Platform.isAndroid || Platform.isIOS))) {
      await _carregarPainel();
    }
  }

  bool _abaVisivelAgora() {
    if (!mounted) return false;
    if (!AppShellAbaVisibilidade.leituraSemDependencia(context)) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    return true;
  }

  void _sincronizarTimersComVisibilidade() {
    if (!mounted) return;
    // Registra dependencia no InheritedWidget da aba.
    final abaAtiva = AppShellAbaVisibilidade.estaAtiva(context);
    final route = ModalRoute.of(context);
    final deveRodar =
        abaAtiva && (route == null || route.isCurrent);
    if (deveRodar == _timersPeriodicosAtivos) return;
    _timersPeriodicosAtivos = deveRodar;
    if (deveRodar) {
      _iniciarTimersPeriodicos();
    } else {
      _pararTimersPeriodicos();
    }
  }

  void _iniciarTimersPeriodicos() {
    _pararTimersPeriodicos();
    _atualizarRelogio();
    _relogioTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_abaVisivelAgora()) return;
      _atualizarRelogio();
    });
    _fiscalPendenciasTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (!_abaVisivelAgora()) return;
        unawaited(_atualizarPendenciasFiscais());
      },
    );
    final deps = MainMenuDeps.maybeOf(context);
    if (deps != null) {
      _iniciarAlertasProativos(deps);
    }
  }

  void _pararTimersPeriodicos() {
    _relogioTimer?.cancel();
    _relogioTimer = null;
    _fiscalPendenciasTimer?.cancel();
    _fiscalPendenciasTimer = null;
    _alertasProativosTimer?.cancel();
    _alertasProativosTimer = null;
  }

  void _iniciarAlertasProativos(MainMenuDeps deps) {
    _alertasProativosTimer?.cancel();
    _alertasProativosService = AlertasProativosService(
      configRepository: deps.appConfigRepository,
      produtoRepository: deps.produtoRepository,
      vendaRepository: deps.vendaRepository,
    );
    // No celular atrasa o 1o disparo (varre produtos/vendas e congela).
    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (celular) {
      _alertasProativosTimer = Timer(const Duration(minutes: 5), () {
        if (!_abaVisivelAgora()) return;
        unawaited(_alertasProativosService?.verificarEEnviarSeDevido());
        _alertasProativosTimer = Timer.periodic(
          const Duration(minutes: 30),
          (_) {
            if (!_abaVisivelAgora()) return;
            unawaited(_alertasProativosService?.verificarEEnviarSeDevido());
          },
        );
      });
      return;
    }
    unawaited(_alertasProativosService!.verificarEEnviarSeDevido());
    _alertasProativosTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) {
        if (!_abaVisivelAgora()) return;
        unawaited(_alertasProativosService?.verificarEEnviarSeDevido());
      },
    );
  }

  @override
  void dispose() {
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    _pararTimersPeriodicos();
    super.dispose();
  }

  Future<void> _atualizarPendenciasFiscais() async {
    if (!mounted) return;
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;
    if (!UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
      deps.usuarioLogado,
    )) {
      return;
    }
    final total = FiscalPendenciasResumoService.contar(
      vendaRepository: deps.vendaRepository,
    ).total;
    final atual = _resumo?.fiscalPendencias ?? -1;
    if (atual == total) return;
    setState(() {
      final r = _resumo;
      if (r == null) return;
      _resumo = _MainMenuResumo(
        vendasHoje: r.vendasHoje,
        faturamentoHoje: r.faturamentoHoje,
        caixaAberto: r.caixaAberto,
        entregasEmAberto: r.entregasEmAberto,
        entregasAtrasadas: r.entregasAtrasadas,
        alertas: r.alertas,
        totalAReceber: r.totalAReceber,
        totalFiadoVencido: r.totalFiadoVencido,
        fiscalPendencias: total,
        backupAlerta: r.backupAlerta,
      );
    });
  }

  void _atualizarRelogio() {
    if (!mounted) return;
    setState(() {
      _dataHoraExibida = _dataHora.format(DateTime.now());
    });
  }

  Future<void> _carregarFavoritos() async {
    final deps = MainMenuDeps.of(context);
    var favs = await MenuFavoritosRepository.carregar(deps.usuarioLogado.login);
    if (favs.isEmpty) {
      favs = MainMenuDestino.favoritosPadrao(deps.usuarioLogado);
      if (favs.isNotEmpty) {
        await MenuFavoritosRepository.salvar(deps.usuarioLogado.login, favs);
      }
    }
    if (!mounted) return;
    setState(() => _favoritos = favs);
  }

  Future<void> _carregarPainel() async {
    if (!mounted) return;
    setState(() => _carregandoResumo = true);

    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    try {
      final deps = MainMenuDeps.of(context);
      final config = await deps.appConfigRepository.carregarEmpresaConfig();
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      final sessao = await CaixaSessaoRepository().carregarSessaoLocal();
      final agora = DateTime.now();
      final inicio = DateTime(agora.year, agora.month, agora.day);
      final fim = inicio
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final u = deps.usuarioLogado;

      // Celular: so KPI do dia + caixa. Nada de entregas/financeiro/alertas/fiscal.
      if (celular) {
        final vendasHoje = deps.vendaRepository
            .listarPorPeriodo(PeriodoFiltro(inicio: inicio, fim: fim))
            .where((v) => !v.cancelada && v.status == 'finalizada');
        final verTotalLoja =
            UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u);
        final vendas = verTotalLoja
            ? vendasHoje
            : vendasHoje.where((v) => v.vendedor.targetId == u.vendedorId);
        final lista = vendas.toList();
        final faturamento = lista.fold<double>(0, (s, v) => s + v.total);
        if (!mounted) return;
        setState(() {
          _config = config;
          _recadosNaoLidos = const [];
          _resumo = _MainMenuResumo(
            vendasHoje: lista.length,
            faturamentoHoje: faturamento,
            caixaAberto: sessao.aberto,
            entregasEmAberto: 0,
            entregasAtrasadas: 0,
            alertas: const [],
            totalAReceber: null,
            totalFiadoVencido: null,
            fiscalPendencias: 0,
            backupAlerta: false,
          );
          _carregandoResumo = false;
        });
        return;
      }

      // Query por data (nao varre todas as vendas do banco).
      final todasVendas = deps.vendaRepository
          .listarPorPeriodo(PeriodoFiltro(inicio: inicio, fim: fim))
          .where((v) => !v.cancelada && v.status == 'finalizada');
      final verTotalLoja =
          UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u);
      final vendas = verTotalLoja
          ? todasVendas
          : todasVendas.where((v) => v.vendedor.targetId == u.vendedorId);
      final listaVendas = vendas.toList();
      final faturamento =
          listaVendas.fold<double>(0, (s, v) => s + v.total);

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      var emAberto = 0;
      var atrasadas = 0;
      if (UsuarioPermissaoHelper.podeVisualizarEntregas(u)) {
        final ent = deps.vendaRepository.contarEntregasPainelResumo();
        emAberto = ent.emAberto;
        atrasadas = ent.atrasadas;
      }

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      deps.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();

      final podeFinanceiro =
          UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro);
      double? totalAReceber;
      double? totalFiadoVencido;
      if (podeFinanceiro) {
        final titulosAbertos =
            deps.vendaRepository.titulos.listarTodosAbertos();
        totalAReceber = titulosAbertos.fold<double>(
          0,
          (s, l) => s + l.titulo.saldo,
        );
        totalFiadoVencido = titulosAbertos
            .where(ContasReceberHelper.ehVencido)
            .fold<double>(0, (s, l) => s + l.titulo.saldo);
      }

      final backupManual =
          await deps.appConfigRepository.carregarRegistroBackupManual();
      final backupStatus = BackupStatusHelper.avaliar(
        config: config,
        manual: backupManual,
      );

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      final alertas = DashboardAlertasService.montar(
        vendaRepository: deps.vendaRepository,
        produtoRepository: deps.produtoRepository,
        objectBox: deps.objectBox,
        podeFinanceiro: podeFinanceiro,
        podeEstoque: UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque),
        podeEntregas: UsuarioPermissaoHelper.podeVisualizarEntregas(u),
        empresaConfig: config,
        backupManual: backupManual,
        podeConfiguracoes: UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.configuracoes,
        ),
        podeOrcamentos: UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u),
      );

      final fiscalPendencias =
          UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(u)
              ? FiscalPendenciasResumoService.contar(
                  vendaRepository: deps.vendaRepository,
                ).total
              : 0;

      final recadoRepo = RecadoLojaRepository(deps.objectBox);
      final recadosNaoLidos = recadoRepo.listarNaoLidosParaUsuario(u);

      if (!mounted) return;
      setState(() {
        _config = config;
        _recadosNaoLidos = recadosNaoLidos;
        _resumo = _MainMenuResumo(
          vendasHoje: listaVendas.length,
          faturamentoHoje: faturamento,
          caixaAberto: sessao.aberto,
          entregasEmAberto: emAberto,
          entregasAtrasadas: atrasadas,
          alertas: alertas,
          totalAReceber: totalAReceber,
          totalFiadoVencido: totalFiadoVencido,
          fiscalPendencias: fiscalPendencias,
          backupAlerta: backupStatus.exibirAlerta,
        );
        _carregandoResumo = false;
      });
    } catch (_) {
      if (mounted) setState(() => _carregandoResumo = false);
    }
  }

  void _abrirAlerta(DashboardAlerta alerta) {
    if (alerta.filtroContasReceber != null) {
      MainMenuRouter.abrirContasReceber(
        context,
        filtro: alerta.filtroContasReceber!,
      );
      return;
    }
    if (alerta.filtroContasPagar != null) {
      MainMenuRouter.abrirContasPagar(
        context,
        filtro: alerta.filtroContasPagar!,
      );
      return;
    }
    if (alerta.destino != null) {
      MainMenuRouter.abrir(
        context,
        alerta.destino!,
        configSecaoInicialId: alerta.configSecaoId,
      );
    }
  }

  bool _tem(PermissaoUsuario p) =>
      UsuarioPermissaoHelper.tem(MainMenuDeps.of(context).usuarioLogado, p);

  void _ir(MainMenuDestino d) => MainMenuRouter.abrir(context, d);

  void _abrirRecados() {
    final deps = MainMenuDeps.of(context);
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RecadosLojaPage(
          objectBox: deps.objectBox,
          usuarioLogado: deps.usuarioLogado,
        ),
      ),
    ).then((_) {
      if (mounted) _carregarPainel();
    });
  }

  void _marcarRecadoLido(RecadoLoja recado) {
    final deps = MainMenuDeps.of(context);
    RecadoLojaRepository(deps.objectBox)
        .marcarLido(recado.id, deps.usuarioLogado.login);
    _carregarPainel();
  }

  void _abrirLojaAoVivo() {
    final deps = MainMenuDeps.of(context);
    if (!UsuarioPermissaoHelper.podeAcessarLojaAoVivo(deps.usuarioLogado)) {
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MainMenuDeps(
          objectBox: deps.objectBox,
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: deps.usuarioLogado,
          onLogout: deps.onLogout,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          child: LojaAoVivoPage(
            vendaRepository: deps.vendaRepository,
            produtoRepository: deps.produtoRepository,
            vendedorRepository: deps.vendedorRepository,
            objectBox: deps.objectBox,
            usuarioLogado: deps.usuarioLogado,
          ),
        ),
      ),
    );
  }

  Future<void> _alternarFavorito(MainMenuDestino d) async {
    final shell = AppShellScope.maybeOf(context);
    if (shell != null) {
      await shell.alternarFavorito(d);
      return;
    }
    final deps = MainMenuDeps.of(context);
    final atual = await MenuFavoritosRepository.alternar(
      login: deps.usuarioLogado.login,
      destino: d,
      podeAcessar: d.podeAcessar(deps.usuarioLogado),
    );
    if (!mounted) return;
    setState(() => _favoritos = atual);
  }

  bool _ehFavorito(MainMenuDestino d) {
    final shell = AppShellScope.maybeOf(context);
    if (shell != null) return shell.ehFavorito(d);
    return _favoritos.contains(d);
  }

  List<MainMenuDestino> get _favoritosVisiveis {
    final shell = AppShellScope.maybeOf(context);
    final lista = shell?.favoritos ?? _favoritos;
    final u = MainMenuDeps.of(context).usuarioLogado;
    return lista.where((d) => d.podeAcessar(u)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final deps = MainMenuDeps.of(context);
    final u = deps.usuarioLogado;
    final podeVendas = _tem(PermissaoUsuario.vendasHub);
    final podeVerMinhasVendas =
        UsuarioPermissaoHelper.podeVerMinhasVendasHoje(u);
    final podeVerTotalLoja =
        UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u);
    final podeLojaAoVivo = UsuarioPermissaoHelper.podeAcessarLojaAoVivo(u);
    final podePdv = _tem(PermissaoUsuario.acessarPdv);
    final podeCaixa = _tem(PermissaoUsuario.acessarCaixa);
    final podeFinanceiro = _tem(PermissaoUsuario.financeiro);
    final podeEntregas = UsuarioPermissaoHelper.podeVisualizarEntregas(u);
    final podeMotorista = UsuarioPermissaoHelper.podeUsarModoMotorista(u);
    final config = _config;
    final resumo = _resumo;
    final tituloAppBar = config != null && config.nomeLoja.trim().isNotEmpty
        ? config.nomeLoja.trim()
        : 'Menu principal';

    final corpo = RefreshIndicator(
      onRefresh: () async {
        await _carregarFavoritos();
        await _carregarPainel();
      },
      child: MainMenuBody(
        child: ValueListenableBuilder<SyncLogEntry?>(
          valueListenable: SyncLog.ultimo,
          builder: (context, syncEntry, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MainMenuContextHeader(
                  nomeLoja: config?.nomeLoja ?? tituloAppBar,
                  dataHoraFormatada: _dataHoraExibida,
                  syncAtivo: config?.redeSincronizacaoAtiva ?? false,
                  syncSucesso: syncEntry?.sucesso,
                  syncMensagem: syncEntry?.mensagem,
                ),
                const SizedBox(height: 16),
                if (_favoritosVisiveis.isNotEmpty) ...[
                  const MainMenuSectionHeader(titulo: 'Favoritos'),
                  MainMenuFavoritosStrip(
                    favoritos: _favoritosVisiveis,
                    onTap: _ir,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_recadosNaoLidos.isNotEmpty) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: MainMenuSectionHeader(titulo: 'Recados'),
                      ),
                      TextButton(
                        onPressed: _abrirRecados,
                        child: const Text('Ver todos'),
                      ),
                    ],
                  ),
                  RecadosLojaFaixa(
                    recados: _recadosNaoLidos,
                    usuario: u,
                    onAbrirTodos: _abrirRecados,
                    onMarcarLido: _marcarRecadoLido,
                  ),
                  const SizedBox(height: 16),
                ],
                if (resumo != null && resumo.alertas.isNotEmpty) ...[
                  const MainMenuSectionHeader(titulo: 'Atencao'),
                  DashboardAlertasStrip(
                    alertas: resumo.alertas,
                    onAlertaTap: _abrirAlerta,
                  ),
                  const SizedBox(height: 16),
                ],
                _faixaKpis(
                  resumo: resumo,
                  podeVendas: podeVerMinhasVendas,
                  rotuloVendas:
                      podeVerTotalLoja ? 'Vendas hoje' : 'Minhas vendas hoje',
                  podeCaixa: podeCaixa,
                  podeEntregas: podeEntregas,
                  podeFinanceiro: podeFinanceiro,
                ),
                const SizedBox(height: 12),
                HubNavButton(
                  icon: Icons.campaign_outlined,
                  corDestaque: Colors.deepPurple.shade400,
                  titulo: 'Recados da loja',
                  subtitulo: _recadosNaoLidos.isEmpty
                      ? 'Avisos para a equipe — nenhum pendente.'
                      : '${_recadosNaoLidos.length} recado(s) nao lido(s). Toque para abrir.',
                  onTap: _abrirRecados,
                ),
                if (podeLojaAoVivo) ...[
                  const SizedBox(height: 12),
                  HubNavButton(
                    icon: Icons.monitor_heart_outlined,
                    corDestaque: AppModuloCores.modulo(
                      context,
                      AppModuloId.lojaAoVivo,
                    ),
                    titulo: 'Loja ao vivo',
                    subtitulo: podeVerTotalLoja
                        ? 'Painel operacional: vendas, caixa, entregas, estoque e metas.'
                        : 'Painel com os indicadores liberados para o seu perfil.',
                    onTap: _abrirLojaAoVivo,
                  ),
                ],
                const SizedBox(height: 20),
                const MainMenuSectionHeader(titulo: 'Operacao'),
                _secaoOperacao(
                  podeVendas: podeVendas,
                  podePdv: podePdv,
                  podeCaixa: podeCaixa,
                  podeEntregas: podeEntregas,
                ),
                if (MainMenuDestino.notasFiscais.podeAcessar(u) ||
                    MainMenuDestino.financeiro.podeAcessar(u)) ...[
                  const SizedBox(height: 16),
                  const MainMenuSectionHeader(titulo: 'Fiscal e financeiro'),
                  MainMenuTileGrid(
                    tiles: [
                      if (MainMenuDestino.notasFiscais.podeAcessar(u))
                        _tileModulo(MainMenuDestino.notasFiscais),
                      if (MainMenuDestino.financeiro.podeAcessar(u))
                        _tileModulo(MainMenuDestino.financeiro),
                    ],
                  ),
                ],
                if (MainMenuDestino.cadastros.podeAcessar(u) ||
                    MainMenuDestino.configuracoes.podeAcessar(u)) ...[
                  const SizedBox(height: 16),
                  const MainMenuSectionHeader(titulo: 'Cadastros e sistema'),
                  MainMenuTileGrid(
                    tiles: [
                      if (MainMenuDestino.cadastros.podeAcessar(u))
                        _tileModulo(MainMenuDestino.cadastros),
                      if (MainMenuDestino.configuracoes.podeAcessar(u))
                        _tileModulo(MainMenuDestino.configuracoes),
                    ],
                  ),
                ],
                if (podeMotorista) ...[
                  const SizedBox(height: 16),
                  const MainMenuSectionHeader(titulo: 'Campo'),
                  MainMenuTileGrid(
                    tiles: [_tileModulo(MainMenuDestino.motorista)],
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    'Toque na estrela de um modulo para fixar nos favoritos '
                    '(ate ${MenuFavoritosRepository.maxFavoritos}).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (!widget.mostrarAppBar) return corpo;

    final noShellDesktop = AppShellScope.maybeOf(context) != null;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onAbrirMenu != null
            ? IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: widget.onAbrirMenu,
              )
            : null,
        automaticallyImplyLeading: widget.onAbrirMenu == null,
        title: Text(tituloAppBar),
        actions: [
          if (SeletorTemaApp.uiCompacta(context))
            IconButton(
              tooltip: 'Temas',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => SeletorTemaApp.mostrarFolha(context),
            ),
          IconButton(
            tooltip: 'Atualizar painel',
            onPressed: _carregarPainel,
            icon: const Icon(Icons.refresh_outlined),
          ),
          ContaSessaoAppBarActions(
            login: u.login,
            onLogout: deps.onLogout,
          ),
        ],
      ),
      body: corpo,
      bottomNavigationBar: noShellDesktop
          ? null
          : AppRodapeStatusBar(
              usuarioLogin: u.login,
              usuarioNome: u.nome,
            ),
    );
  }

  Widget _tileModulo(MainMenuDestino d) {
    final u = MainMenuDeps.of(context).usuarioLogado;
    final habilitado = d.podeAcessar(u);
    final podeBadgeFiscal =
        UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(u);
    final badge = d == MainMenuDestino.notasFiscais && podeBadgeFiscal
        ? (_resumo?.fiscalPendencias ?? 0)
        : d == MainMenuDestino.configuracoes && (_resumo?.backupAlerta ?? false)
            ? 1
            : null;
    return MainMenuModuleTile(
      icon: d.icone,
      corDestaque: d.cor(context),
      titulo: d.titulo,
      subtitulo: d.subtitulo,
      habilitado: habilitado,
      favorito: _ehFavorito(d),
      badgeContagem: badge != null && badge > 0 ? badge : null,
      onAlternarFavorito: habilitado ? () => _alternarFavorito(d) : null,
      onTap: () => _ir(d),
    );
  }

  Widget _faixaKpis({
    required _MainMenuResumo? resumo,
    required bool podeVendas,
    required String rotuloVendas,
    required bool podeCaixa,
    required bool podeEntregas,
    required bool podeFinanceiro,
  }) {
    final fmt = _moeda.format(resumo?.faturamentoHoje ?? 0);
    final vendasDet = resumo == null
        ? null
        : '${resumo.vendasHoje} venda${resumo.vendasHoje == 1 ? '' : 's'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final empilhado = constraints.maxWidth < 720;
        final kpis = <Widget>[
          if (podeVendas)
            MainMenuKpiCard(
              icone: Icons.trending_up_outlined,
              rotulo: rotuloVendas,
              valor: 'R\$ $fmt',
              detalhe: vendasDet,
              cor: HubNavColors.menuVendas(context),
              carregando: _carregandoResumo,
              onTap: () => _ir(MainMenuDestino.vendas),
            ),
          if (podeFinanceiro)
            MainMenuKpiCard(
              icone: Icons.call_received_outlined,
              rotulo: 'A receber',
              valor: 'R\$ ${_moeda.format(resumo?.totalAReceber ?? 0)}',
              detalhe: (resumo?.totalFiadoVencido ?? 0) > 0
                  ? 'Vencido: R\$ ${_moeda.format(resumo!.totalFiadoVencido!)}'
                  : 'Fiado em aberto',
              cor: AppModuloCores.modulo(context, AppModuloId.contasReceber),
              carregando: _carregandoResumo,
              onTap: () => MainMenuRouter.abrirContasReceber(context),
            ),
          if (podeCaixa)
            MainMenuKpiCard(
              icone: Icons.account_balance_wallet_outlined,
              rotulo: 'Caixa',
              valor: resumo?.caixaAberto == true ? 'Aberto' : 'Fechado',
              detalhe: resumo?.caixaAberto == true
                  ? 'Operacao em andamento'
                  : 'Toque para abrir o caixa',
              cor: resumo?.caixaAberto == true
                  ? MainMenuDestino.caixa.cor(context)
                  : AppModuloCores.modulo(context, AppModuloId.inativo),
              carregando: _carregandoResumo,
              onTap: () => _ir(MainMenuDestino.caixa),
            ),
          if (podeEntregas)
            MainMenuKpiCard(
              icone: Icons.local_shipping_outlined,
              rotulo: 'Entregas',
              valor: '${resumo?.entregasEmAberto ?? 0} em aberto',
              detalhe: (resumo?.entregasAtrasadas ?? 0) > 0
                  ? '${resumo!.entregasAtrasadas} atrasada(s)'
                  : 'Agenda e expedicao',
              cor: MainMenuDestino.entregas.cor(context),
              carregando: _carregandoResumo,
              onTap: () => _ir(MainMenuDestino.entregas),
            ),
        ];

        if (kpis.isEmpty) return const SizedBox.shrink();

        if (empilhado) {
          return Column(
            children: [
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                kpis[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < kpis.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i > 0 ? 6 : 0,
                    right: i < kpis.length - 1 ? 6 : 0,
                  ),
                  child: kpis[i],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _secaoOperacao({
    required bool podeVendas,
    required bool podePdv,
    required bool podeCaixa,
    required bool podeEntregas,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= AppBreakpoints.desktop;

        final vendas = MainMenuFeaturedVendasTile(
          habilitado: podeVendas,
          onAbrirVendas: () => _ir(MainMenuDestino.vendas),
          onNovaVenda: () => _ir(MainMenuDestino.pdv),
          onCaixa: () => _ir(MainMenuDestino.caixa),
          podePdv: podePdv,
          podeCaixa: podeCaixa,
        );

        final estoque = _tileModulo(MainMenuDestino.estoque);
        final entregas = _tileModulo(MainMenuDestino.entregas);

        if (desktop) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: vendas),
                  const SizedBox(width: 12),
                  Expanded(child: estoque),
                ],
              ),
              if (podeEntregas) ...[
                const SizedBox(height: 12),
                MainMenuTileGrid(tiles: [entregas]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vendas,
            const SizedBox(height: 12),
            MainMenuTileGrid(
              tiles: [
                estoque,
                if (podeEntregas) entregas,
              ],
            ),
          ],
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/api/caixa_sessao_api.dart';
import '../../data/api/lan_api_client.dart';
import '../../data/api/lan_api_event_hub.dart';
import '../../data/api/lan_api_url.dart';
import '../../data/api/recado_loja_api_repository.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../data/menu_favoritos_repository.dart';
import '../../data/recado_loja_repository.dart';
import '../../data/sync/caixa_local_refresh_hub.dart';
import '../../data/sync/caixa_status_hub.dart';
import '../../data/sync/sync_refresh_hub.dart';
import '../../data/venda_repository.dart';
import '../../domain/backup_status_helper.dart';
import '../../domain/dashboard_alertas.dart';
import '../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/caixa_sessao.dart';
import '../../model/recado_loja.dart';
import '../../model/venda.dart';
import '../../services/lan_api_server.dart';
import 'loja_ao_vivo_page.dart';
import 'layout/app_layout.dart';
import 'listagem_vendas_page.dart';
import 'shell/app_shell_aba_visibilidade.dart';
import 'shell/hub_navigation.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';
import 'widgets/seletor_fundo_app.dart';
import 'widgets/seletor_tema_app.dart';
import 'recados_loja_page.dart';
import 'widgets/recados_loja_faixa.dart';
import 'widgets/dashboard_alertas_strip.dart';
import 'widgets/app_rodape_status_bar.dart';
import 'widgets/lan_api_feedback.dart';
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
  List<MainMenuDestino> _favoritos = const [];
  List<RecadoLoja> _recadosNaoLidos = const [];
  Timer? _fiscalPendenciasTimer;
  Timer? _kpiPeriodicoTimer;
  Timer? _painelApiDebounce;
  bool _timersPeriodicosAtivos = false;
  bool? _apiOnlineAnterior;
  VoidCallback? _syncHubListener;
  VoidCallback? _apiHubListener;
  VoidCallback? _caixaLocalListener;
  VoidCallback? _caixaStatusListener;

  static const _entidadesPainel = {
    'venda',
    'entrega',
    'caixa',
    'caixa_sessoes',
    'titulo_receber',
    'recebimento_fiado',
    'conta_pagar',
    'financeiro',
    'recado_loja',
  };

  @override
  void initState() {
    super.initState();
    _syncHubListener = () {
      if (!mounted) return;
      // Celular: sync nao deve forcar rebuild do painel (ANR).
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return;
      // Debounce: finalizar venda dispara venda + titulo + estoque juntos.
      _painelApiDebounce?.cancel();
      _painelApiDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) unawaited(_carregarPainel(silencioso: true));
      });
    };
    SyncRefreshHub.instance.addListener(_syncHubListener!);
    _apiOnlineAnterior = LanApiEventHub.instance.online;
    _apiHubListener = () {
      if (!mounted) return;
      setState(() {});
      final hub = LanApiEventHub.instance;
      final online = hub.online;
      final ficouOnline = online && _apiOnlineAnterior == false;
      _apiOnlineAnterior = online;
      if (!ficouOnline && !_entidadesPainel.contains(hub.ultimaEntidade)) {
        return;
      }
      // Caixa: atualiza KPI mesmo com Inicio em segundo plano.
      final silenciosoCaixa = hub.ultimaEntidade == 'caixa' ||
          hub.ultimaEntidade == 'caixa_sessoes';
      if (!silenciosoCaixa && !_abaVisivelAgora()) return;
      _painelApiDebounce?.cancel();
      _painelApiDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          unawaited(_carregarPainel(silencioso: true));
        }
      });
    };
    LanApiEventHub.instance.addListener(_apiHubListener!);
    _caixaLocalListener = () {
      if (!mounted) return;
      // Debounce: evitar rajada (abrir aba + hub + sync) travando a UI.
      _painelApiDebounce?.cancel();
      _painelApiDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) unawaited(_carregarPainel(silencioso: true));
      });
    };
    CaixaLocalRefreshHub.instance.addListener(_caixaLocalListener!);
    _caixaStatusListener = () {
      if (!mounted) return;
      final aberto = CaixaStatusHub.instance.lojaAberta;
      final atual = _resumo;
      // Nao inventar KPI de vendas zerado antes do carregamento real.
      if (atual == null) return;
      if (atual.caixaAberto == aberto) return;
      setState(() {
        _resumo = _MainMenuResumo(
          vendasHoje: atual.vendasHoje,
          faturamentoHoje: atual.faturamentoHoje,
          caixaAberto: aberto,
          entregasEmAberto: atual.entregasEmAberto,
          entregasAtrasadas: atual.entregasAtrasadas,
          alertas: atual.alertas,
          totalAReceber: atual.totalAReceber,
          totalFiadoVencido: atual.totalFiadoVencido,
          fiscalPendencias: atual.fiscalPendencias,
          backupAlerta: atual.backupAlerta,
        );
      });
    };
    CaixaStatusHub.instance.addListener(_caixaStatusListener!);
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

    // KPIs primeiro — nunca esperar bootstrap de rede.
    await _carregarFavoritos();
    if (!CaixaStatusHub.instance.hidratado) {
      await CaixaStatusHub.instance.sincronizarDoRepositorio();
    }
    await _carregarPainel();
    if (mounted) _sincronizarTimersComVisibilidade();

    // PC servidor / celular: sobe API ou scheduler em segundo plano.
    // Terminal leve: no-op (sem sync P2P).
    unawaited(_bootstrapRedeEmSegundoPlano(deps));
  }

  Future<void> _bootstrapRedeEmSegundoPlano(MainMenuDeps deps) async {
    if (deps.terminalLeve) return;
    try {
      if (widget.onIniciarSync != null) {
        await widget.onIniciarSync!();
      } else if (deps.lanSyncScheduler != null) {
        // Celular legado: scheduler de catalogo (sem API terminal).
        await deps.lanSyncScheduler!.iniciar();
      }
    } catch (_) {
      // Bootstrap falhou: painel ja foi carregado com dados locais/API.
    }
    if (mounted && (kIsWeb || !(Platform.isAndroid || Platform.isIOS))) {
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
    final deveRodar = abaAtiva && (route == null || route.isCurrent);
    if (deveRodar == _timersPeriodicosAtivos) return;
    final ficouVisivel = deveRodar && !_timersPeriodicosAtivos;
    _timersPeriodicosAtivos = deveRodar;
    if (deveRodar) {
      _iniciarTimersPeriodicos();
      if (ficouVisivel) unawaited(_carregarPainel());
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
    final deps = MainMenuDeps.maybeOf(context);
    // Terminal leve: KPIs via API periodica (sem ObjectBox local).
    if (deps?.terminalLeve == true) {
      _kpiPeriodicoTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (!_abaVisivelAgora()) return;
        unawaited(_carregarPainel(silencioso: true));
      });
      return;
    }
    // PC servidor: tambem atualiza KPI periodicamente (venda local nao
    // depende so do SyncRefreshHub se a aba ficou aberta).
    _kpiPeriodicoTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_abaVisivelAgora()) return;
      unawaited(_carregarPainel(silencioso: true));
    });
    _fiscalPendenciasTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_abaVisivelAgora()) return;
      unawaited(_atualizarPendenciasFiscais());
    });
  }

  void _pararTimersPeriodicos() {
    _relogioTimer?.cancel();
    _relogioTimer = null;
    _fiscalPendenciasTimer?.cancel();
    _fiscalPendenciasTimer = null;
    _kpiPeriodicoTimer?.cancel();
    _kpiPeriodicoTimer = null;
  }

  @override
  void dispose() {
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
      _syncHubListener = null;
    }
    if (_apiHubListener != null) {
      LanApiEventHub.instance.removeListener(_apiHubListener!);
      _apiHubListener = null;
    }
    if (_caixaLocalListener != null) {
      CaixaLocalRefreshHub.instance.removeListener(_caixaLocalListener!);
      _caixaLocalListener = null;
    }
    if (_caixaStatusListener != null) {
      CaixaStatusHub.instance.removeListener(_caixaStatusListener!);
      _caixaStatusListener = null;
    }
    _painelApiDebounce?.cancel();
    _painelApiDebounce = null;
    _pararTimersPeriodicos();
    super.dispose();
  }

  /// Badge de conexao API (substitui o antigo "Sync LAN").
  MainMenuApiStatus? _statusApiCabecalho(MainMenuDeps deps) {
    final porta = LanApiUrl.portaPadrao;
    if (deps.terminalLeve) {
      final online = LanApiEventHub.instance.online;
      return MainMenuApiStatus(
        online: online,
        rotulo: online ? 'Conectado · :$porta' : 'Offline',
        tooltip: online
            ? 'Conectado ao servidor na porta $porta'
            : 'Sem conexao com a API do PC servidor (:$porta)',
      );
    }
    final cfg = _config;
    if (cfg != null &&
        cfg.redeSincronizacaoAtiva &&
        cfg.redeModoServidor) {
      final ativo = LanApiServerHub.instance.ativo;
      return MainMenuApiStatus(
        online: ativo,
        rotulo: ativo ? 'API ativa · :$porta' : 'API offline',
        tooltip: ativo
            ? 'API de terminais ativa na porta $porta'
            : 'Modo servidor ativo, mas a API :$porta ainda nao subiu',
      );
    }
    return null;
  }

  Future<void> _atualizarPendenciasFiscais() async {
    if (!mounted) return;
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null || deps.terminalLeve || deps.objectBox == null) return;
    if (deps.vendaRepository is! VendaRepository) return;
    if (!UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
      deps.usuarioLogado,
    )) {
      return;
    }
    final total = FiscalPendenciasResumoService.contar(
      vendaRepository: deps.vendaRepository as VendaRepository,
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

  Future<void> _carregarPainel({bool silencioso = false}) async {
    if (!mounted) return;
    if (!silencioso) {
      setState(() => _carregandoResumo = true);
    }

    final celular = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    try {
      final deps = MainMenuDeps.of(context);
      if (deps.terminalLeve) {
        final config = await deps.appConfigRepository.carregarEmpresaConfig();
        // Mantem ultimo KPI bom se a API falhar (evita zerar a tela).
        var resumo = _resumo ??
            const _MainMenuResumo(
              vendasHoje: 0,
              faturamentoHoje: 0,
              caixaAberto: false,
              entregasEmAberto: 0,
              entregasAtrasadas: 0,
              alertas: [],
            );
        final client = deps.lanApiClient;
        if (client != null) {
          try {
            final u = deps.usuarioLogado;
            final verTotalLoja =
                UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u);
            final m = await client.obterDashboardResumo(
              dia: DateTime.now(),
              vendedorId: verTotalLoja ? null : u.vendedorId,
            );
            final podeFinanceiro = UsuarioPermissaoHelper.tem(
              u,
              PermissaoUsuario.financeiro,
            );
            resumo = _MainMenuResumo(
              vendasHoje: (m['vendasHoje'] as num?)?.toInt() ?? 0,
              faturamentoHoje:
                  (m['faturamentoHoje'] as num?)?.toDouble() ?? 0,
              caixaAberto: CaixaSessao.boolFrom(m['caixaAberto']) ||
                  ((m['caixaAbertosCount'] as num?)?.toInt() ?? 0) > 0 ||
                  CaixaStatusHub.instance.lojaAberta,
              entregasEmAberto:
                  (m['entregasEmAberto'] as num?)?.toInt() ?? 0,
              entregasAtrasadas:
                  (m['entregasAtrasadas'] as num?)?.toInt() ?? 0,
              alertas: const [],
              totalAReceber: podeFinanceiro
                  ? (m['totalAReceber'] as num?)?.toDouble()
                  : null,
              totalFiadoVencido: podeFinanceiro
                  ? (m['aReceberVencido'] as num?)?.toDouble()
                  : null,
            );
            // Mesma fonte da tela Caixa (sessao-ativa) — evita KPI desatualizado.
            if (!resumo.caixaAberto) {
              try {
                final tid = await CaixaSessaoRepository().obterTerminalId();
                final snap = await CaixaSessaoApi(client).sessaoAtiva(
                  terminalId: tid,
                );
                final aberta = snap.aberta?.aberto == true ||
                    snap.operacaoLiberada ||
                    snap.terminais.values.any((s) => s.aberto);
                if (aberta) {
                  CaixaStatusHub.instance.publicarDasSessoes(snap.terminais);
                  if (snap.aberta != null) {
                    CaixaStatusHub.instance.publicar(
                      aberto: true,
                      operador: snap.aberta!.operador,
                      terminalId: snap.aberta!.terminalId,
                    );
                  }
                  resumo = _MainMenuResumo(
                    vendasHoje: resumo.vendasHoje,
                    faturamentoHoje: resumo.faturamentoHoje,
                    caixaAberto: true,
                    entregasEmAberto: resumo.entregasEmAberto,
                    entregasAtrasadas: resumo.entregasAtrasadas,
                    alertas: resumo.alertas,
                    totalAReceber: resumo.totalAReceber,
                    totalFiadoVencido: resumo.totalFiadoVencido,
                    fiscalPendencias: resumo.fiscalPendencias,
                    backupAlerta: resumo.backupAlerta,
                  );
                }
              } catch (e) {
                debugPrint('MainMenuDashboard.sessaoAtivaCaixa: $e');
              }
            } else if (resumo.caixaAberto &&
                !CaixaStatusHub.instance.lojaAberta) {
              CaixaStatusHub.instance.publicar(aberto: true);
            }
          } on LanApiException catch (e) {
            debugPrint('MainMenuDashboard.obterDashboardResumo: $e');
            if (!silencioso && mounted) {
              LanApiFeedback.snackAviso(
                context,
                e,
                prefixo: 'Painel',
              );
            }
          } catch (e) {
            debugPrint('MainMenuDashboard.obterDashboardResumo: $e');
            if (!silencioso && mounted) {
              LanApiFeedback.snackAviso(
                context,
                e,
                prefixo: 'Painel',
              );
            }
          }
        }
        List<RecadoLoja> recadosNaoLidos = const [];
        final recadoRepo = deps.recadoLojaRepository;
        if (recadoRepo != null) {
          try {
            if (recadoRepo is RecadoLojaApiRepository) {
              await recadoRepo.hidratar();
            }
            recadosNaoLidos = List<RecadoLoja>.from(
              recadoRepo.listarNaoLidosParaUsuario(deps.usuarioLogado),
            );
          } catch (e) {
            debugPrint('MainMenuDashboard.recados: $e');
          }
        }
        if (!mounted) return;
        setState(() {
          _config = config;
          _recadosNaoLidos = recadosNaoLidos;
          _resumo = resumo;
          _carregandoResumo = false;
        });
        return;
      }
      final config = await deps.appConfigRepository.carregarEmpresaConfig();
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      // Status da loja (qualquer terminal), alinhado a /api/dashboard/resumo.
      final sessoesCaixa =
          await CaixaSessaoRepository().listarTodasSessoes();
      final fromPrefs = sessoesCaixa.values.any((s) => s.aberto);
      // Nao sobrescrever hub "aberto" com prefs vazios/atrasados.
      if (fromPrefs) {
        CaixaStatusHub.instance.publicarDasSessoes(sessoesCaixa);
      }
      final caixaAbertoLoja =
          fromPrefs || CaixaStatusHub.instance.lojaAberta;
      final agora = DateTime.now();
      final u = deps.usuarioLogado;
      final verTotalLoja = UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u);

      // Mesma fonte da Listagem de vendas (periodo "hoje") — evita divergencia.
      final inicioDia = DateTime(agora.year, agora.month, agora.day);
      final fimDia =
          DateTime(agora.year, agora.month, agora.day, 23, 59, 59, 999);
      List<Venda> listaVendas;
      try {
        if (!verTotalLoja && u.vendedorId <= 0) {
          listaVendas = <Venda>[];
        } else {
          final filtro = FiltroListagemVendas(
            textoBusca: '',
            dataInicioUtc: inicioDia.toUtc(),
            dataFimUtc: fimDia.toUtc(),
            filtroCancelamento: 'ativas',
            canceladaPorFiltro: 'todos',
            formaPagamento: 'todos',
            tipoEntrega: 'todos',
            entregaPendente: 'todos',
            filtroFiscal: 'todos',
            vendedorId: verTotalLoja ? null : u.vendedorId,
          );
          listaVendas = List<Venda>.from(
            deps.vendaRepository.listarListagemVendasCompleto(filtro),
          );
          // Complemento: orcamento antigo finalizado hoje (data fora do dia).
          if (deps.vendaRepository is VendaRepository) {
            final extra = (deps.vendaRepository as VendaRepository)
                .listarVendasFinalizadasNoDiaLocal(agora);
            final ids = listaVendas.map((v) => v.id).toSet();
            for (final v in extra) {
              if (ids.contains(v.id)) continue;
              if (!verTotalLoja && v.vendedor.targetId != u.vendedorId) {
                continue;
              }
              listaVendas.add(v);
              ids.add(v.id);
            }
          }
        }
      } catch (e) {
        debugPrint('MainMenuDashboard.vendasHoje: $e');
        listaVendas = <Venda>[];
      }
      final faturamento = listaVendas.fold<double>(0, (s, v) => s + v.total);

      // Celular: so KPI do dia + caixa. Nada de entregas/financeiro/alertas/fiscal.
      if (celular) {
        List<RecadoLoja> recadosCelular = const [];
        final ob = deps.objectBox;
        if (ob != null) {
          try {
            recadosCelular =
                RecadoLojaRepository(ob).listarNaoLidosParaUsuario(u);
          } catch (e) {
            debugPrint('MainMenuDashboard.recados: $e');
          }
        }
        if (!mounted) return;
        setState(() {
          _config = config;
          _recadosNaoLidos = recadosCelular;
          _resumo = _MainMenuResumo(
            vendasHoje: listaVendas.length,
            faturamentoHoje: faturamento,
            caixaAberto: caixaAbertoLoja,
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

      // Grava o KPI imediatamente — o restante do painel nao pode zerar vendas.
      if (mounted) {
        final atual = _resumo;
        setState(() {
          _resumo = _MainMenuResumo(
            vendasHoje: listaVendas.length,
            faturamentoHoje: faturamento,
            caixaAberto: caixaAbertoLoja,
            entregasEmAberto: atual?.entregasEmAberto ?? 0,
            entregasAtrasadas: atual?.entregasAtrasadas ?? 0,
            alertas: atual?.alertas ?? const [],
            totalAReceber: atual?.totalAReceber,
            totalFiadoVencido: atual?.totalFiadoVencido,
            fiscalPendencias: atual?.fiscalPendencias ?? 0,
            backupAlerta: atual?.backupAlerta ?? false,
          );
        });
      }

      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      var emAberto = 0;
      var atrasadas = 0;
      double? totalAReceber;
      double? totalFiadoVencido;
      var alertas = const <DashboardAlerta>[];
      var fiscalPendencias = 0;
      var backupAlerta = false;
      List<RecadoLoja> recadosNaoLidos = const [];

      try {
        if (UsuarioPermissaoHelper.podeAcessarModuloEntregas(u)) {
          final ent = deps.vendaRepository.contarEntregasPainelResumo();
          emAberto = ent.emAberto;
          atrasadas = ent.atrasadas;
        }

        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;

        try {
          deps.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
        } catch (e) {
          debugPrint('MainMenuDashboard.migrarTitulos: $e');
        }

        final podeFinanceiro = UsuarioPermissaoHelper.tem(
          u,
          PermissaoUsuario.financeiro,
        );
        if (podeFinanceiro) {
          final titulosAbertos = deps.vendaRepository.titulos
              .listarTodosAbertos();
          totalAReceber = titulosAbertos.fold<double>(
            0,
            (s, l) => s + l.titulo.saldo,
          );
          totalFiadoVencido = titulosAbertos
              .where(ContasReceberHelper.ehVencido)
              .fold<double>(0, (s, l) => s + l.titulo.saldo);
        }

        final backupManual = await deps.appConfigRepository
            .carregarRegistroBackupManual();
        final backupStatus = BackupStatusHelper.avaliar(
          config: config,
          manual: backupManual,
        );
        backupAlerta = backupStatus.exibirAlerta;

        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;

        alertas = DashboardAlertasService.montar(
          vendaRepository: deps.vendaRepository,
          produtoRepository: deps.produtoRepository,
          objectBox: deps.objectBox!,
          podeFinanceiro: podeFinanceiro,
          podeEstoque: UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque),
          podeEntregas: UsuarioPermissaoHelper.podeAcessarModuloEntregas(u),
          empresaConfig: config,
          backupManual: backupManual,
          podeConfiguracoes: UsuarioPermissaoHelper.tem(
            u,
            PermissaoUsuario.configuracoes,
          ),
          podeOrcamentos: UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u),
        );

        fiscalPendencias =
            UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(u) &&
                    deps.vendaRepository is VendaRepository
                ? FiscalPendenciasResumoService.contar(
                    vendaRepository: deps.vendaRepository as VendaRepository,
                  ).total
                : 0;
      } catch (e, st) {
        debugPrint('MainMenuDashboard.painelSecundario: $e\n$st');
      }

      try {
        recadosNaoLidos = RecadoLojaRepository(deps.objectBox!)
            .listarNaoLidosParaUsuario(u);
      } catch (e) {
        debugPrint('MainMenuDashboard.recados: $e');
      }

      if (!mounted) return;
      setState(() {
        _config = config;
        _recadosNaoLidos = recadosNaoLidos;
        _resumo = _MainMenuResumo(
          vendasHoje: listaVendas.length,
          faturamentoHoje: faturamento,
          caixaAberto: caixaAbertoLoja,
          entregasEmAberto: emAberto,
          entregasAtrasadas: atrasadas,
          alertas: alertas,
          totalAReceber: totalAReceber,
          totalFiadoVencido: totalFiadoVencido,
          fiscalPendencias: fiscalPendencias,
          backupAlerta: backupAlerta,
        );
        _carregandoResumo = false;
      });
      return;
    } catch (e, st) {
      debugPrint('MainMenuDashboard._carregarPainel: $e\n$st');
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
    final repo = deps.recadoLojaRepository;
    final ob = deps.objectBox;
    if (repo == null && ob == null) {
      if (deps.lanApiClient != null && deps.lanApiClient!.configurado) {
        // Fallback: abre via API mesmo sem repo injetado.
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => deps.wrap(
              RecadosLojaPage(
                usuarioLogado: deps.usuarioLogado,
              ),
            ),
          ),
        ).then((_) {
          if (mounted) unawaited(_carregarPainel());
        });
        return;
      }
      _mostrarIndisponivelNoTerminalLeve();
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => deps.wrap(
          RecadosLojaPage(
            objectBox: ob,
            recadoRepository: repo,
            usuarioLogado: deps.usuarioLogado,
          ),
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(_carregarPainel());
    });
  }

  Future<void> _marcarRecadoLido(RecadoLoja recado) async {
    final deps = MainMenuDeps.of(context);
    final repo = deps.recadoLojaRepository;
    try {
      if (deps.terminalLeve &&
          LanApiEventHub.instance.deveBloquearOperacoes) {
        LanApiFeedback.snackAviso(
          context,
          LanApiEventHub.msgServidorOffline,
          prefixo: 'Recados',
        );
        return;
      }
      if (repo != null) {
        final r = repo.marcarLido(recado.id, deps.usuarioLogado.login);
        if (r is Future) await r;
      } else if (deps.objectBox != null) {
        RecadoLojaRepository(
          deps.objectBox!,
        ).marcarLido(recado.id, deps.usuarioLogado.login);
      } else {
        _mostrarIndisponivelNoTerminalLeve();
        return;
      }
      if (mounted) unawaited(_carregarPainel(silencioso: true));
    } catch (e) {
      if (!mounted) return;
      if (deps.terminalLeve) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Recados');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _abrirLojaAoVivo() {
    final deps = MainMenuDeps.of(context);
    if (!UsuarioPermissaoHelper.podeAcessarLojaAoVivo(deps.usuarioLogado)) {
      return;
    }
    final terminal = deps.terminalLeve || deps.objectBox == null;
    if (terminal &&
        (deps.lanApiClient == null || !deps.lanApiClient!.configurado)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Loja ao vivo indisponivel: conecte ao PC servidor (API :8788).',
          ),
        ),
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => deps.wrap(
          LojaAoVivoPage(
            vendaRepository: deps.vendaRepository,
            produtoRepository: deps.produtoRepository,
            vendedorRepository: deps.vendedorRepository,
            objectBox: deps.objectBox,
            lanApiClient: deps.lanApiClient,
            terminalLeve: deps.terminalLeve,
            usuarioLogado: deps.usuarioLogado,
          ),
        ),
      ),
    );
  }

  void _mostrarIndisponivelNoTerminalLeve() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recurso disponivel apenas no PC servidor.'),
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
    final podeVerMinhasVendas = UsuarioPermissaoHelper.podeVerMinhasVendasHoje(
      u,
    );
    final podeVerTotalLoja = UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(
      u,
    );
    final podeLojaAoVivo = UsuarioPermissaoHelper.podeAcessarLojaAoVivo(u);
    final podeUsarRecados = deps.objectBox != null ||
        deps.recadoLojaRepository != null ||
        (deps.lanApiClient != null && deps.lanApiClient!.configurado);
    final podeUsarLojaAoVivo = podeLojaAoVivo &&
        ((!deps.terminalLeve && deps.objectBox != null) ||
            (deps.lanApiClient != null && deps.lanApiClient!.configurado));
    final podePdv = _tem(PermissaoUsuario.acessarPdv);
    final podeCaixa = _tem(PermissaoUsuario.acessarCaixa);
    final podeFinanceiro = _tem(PermissaoUsuario.financeiro);
    final podeEntregas = UsuarioPermissaoHelper.podeAcessarModuloEntregas(u);
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MainMenuContextHeader(
              nomeLoja: config?.nomeLoja ?? tituloAppBar,
              dataHoraFormatada: _dataHoraExibida,
              statusApi: _statusApiCabecalho(deps),
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
              rotuloVendas: podeVerTotalLoja
                  ? 'Vendas hoje'
                  : 'Minhas vendas hoje',
              podeCaixa: podeCaixa,
              podeEntregas: podeEntregas,
              podeFinanceiro: podeFinanceiro,
            ),
            const SizedBox(height: 12),
            if (podeUsarRecados)
              HubNavButton(
                icon: Icons.campaign_outlined,
                corDestaque: Colors.deepPurple.shade400,
                titulo: 'Recados da loja',
                subtitulo: _recadosNaoLidos.isEmpty
                    ? 'Avisos para a equipe — nenhum pendente.'
                    : '${_recadosNaoLidos.length} recado(s) nao lido(s). Toque para abrir.',
                onTap: _abrirRecados,
              ),
            if (podeUsarLojaAoVivo) ...[
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
          if (SeletorTemaApp.uiCompacta(context)) ...[
            IconButton(
              tooltip: 'Temas',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => SeletorTemaApp.mostrarFolha(context),
            ),
            IconButton(
              tooltip: 'Plano de fundo',
              icon: const Icon(Icons.wallpaper_outlined),
              onPressed: () => SeletorFundoApp.mostrarFolha(context),
            ),
          ],
          IconButton(
            tooltip: 'Atualizar painel',
            onPressed: _carregarPainel,
            icon: const Icon(Icons.refresh_outlined),
          ),
          ContaSessaoAppBarActions(login: u.login, onLogout: deps.onLogout),
        ],
      ),
      body: corpo,
      bottomNavigationBar: noShellDesktop
          ? null
          : AppRodapeStatusBar(usuarioLogin: u.login, usuarioNome: u.nome),
    );
  }

  Widget _tileModulo(MainMenuDestino d) {
    final u = MainMenuDeps.of(context).usuarioLogado;
    final habilitado = d.podeAcessar(u);
    final podeBadgeFiscal = UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(
      u,
    );
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
        : (resumo.vendasHoje <= 0
            ? 'Nenhuma finalizada hoje — toque para ver'
            : '${resumo.vendasHoje} venda${resumo.vendasHoje == 1 ? '' : 's'} finalizada${resumo.vendasHoje == 1 ? '' : 's'}');

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
              onTap: () {
                // Listagem de vendas finalizadas (nao hub/orcamentos).
                final u = MainMenuDeps.of(context).usuarioLogado;
                if (MainMenuSubDestino.vendasListagem.podeAcessar(u)) {
                  ListagemVendasAbertura.agendarPeriodo('hoje');
                  HubNavigation.abrirSub(
                    context,
                    MainMenuSubDestino.vendasListagem,
                  );
                  return;
                }
                _ir(MainMenuDestino.vendas);
              },
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
              onTap: () => MainMenuRouter.abrirContasReceber(context).then((_) {
                if (mounted) unawaited(_carregarPainel(silencioso: true));
              }),
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
            MainMenuTileGrid(tiles: [estoque, if (podeEntregas) entregas]),
          ],
        );
      },
    );
  }
}

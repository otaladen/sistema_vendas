import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_config_repository.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../data/menu_favoritos_repository.dart';
import '../../data/sync/sync_log.dart';
import '../../data/venda_repository.dart';
import '../../domain/filtro_listagem_entregas.dart';
import '../../domain/backup_status_helper.dart';
import '../../domain/dashboard_alertas.dart';
import '../../domain/fiscal/fiscal_pendencias_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../services/alertas_proativos_service.dart';
import '../../services/lan_sync_server_manager.dart';
import 'loja_ao_vivo_page.dart';
import 'layout/app_layout.dart';
import 'relatorios/relatorio_entregas_helper.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';
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
  });

  final bool mostrarAppBar;
  final Future<void> Function()? onIniciarSync;

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
  Timer? _fiscalPendenciasTimer;

  @override
  void initState() {
    super.initState();
    _atualizarRelogio();
    _relogioTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _atualizarRelogio();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _inicializar());
    _fiscalPendenciasTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_atualizarPendenciasFiscais()),
    );
  }

  Future<void> _inicializar() async {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;
    if (widget.onIniciarSync != null) {
      await widget.onIniciarSync!();
    } else {
      final config = await deps.appConfigRepository.carregarEmpresaConfig();
      if (Platform.isWindows &&
          config.redeModoServidor &&
          config.redeSincronizacaoAtiva) {
        await LanSyncServerManager.iniciarServidor(
          porta: config.redePortaServidor,
        );
      }
      await deps.lanSyncScheduler.iniciar();
    }
    await _carregarFavoritos();
    await _carregarPainel();
    _iniciarAlertasProativos(deps);
  }

  void _iniciarAlertasProativos(MainMenuDeps deps) {
    _alertasProativosTimer?.cancel();
    _alertasProativosService = AlertasProativosService(
      configRepository: deps.appConfigRepository,
      produtoRepository: deps.produtoRepository,
      vendaRepository: deps.vendaRepository,
    );
    unawaited(_alertasProativosService!.verificarEEnviarSeDevido());
    _alertasProativosTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(_alertasProativosService?.verificarEEnviarSeDevido()),
    );
  }

  @override
  void dispose() {
    _relogioTimer?.cancel();
    _alertasProativosTimer?.cancel();
    _fiscalPendenciasTimer?.cancel();
    super.dispose();
  }

  Future<void> _atualizarPendenciasFiscais() async {
    if (!mounted) return;
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null) return;
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

    final deps = MainMenuDeps.of(context);
    final config = await deps.appConfigRepository.carregarEmpresaConfig();
    final sessao = await CaixaSessaoRepository().carregarSessaoLocal();
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, agora.day);
    final fim = inicio
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    final vendas = deps.vendaRepository
        .listarPorPeriodo(PeriodoFiltro(inicio: inicio, fim: fim))
        .where((v) => !v.cancelada && v.status == 'finalizada');
    final faturamento = vendas.fold<double>(0, (s, v) => s + v.total);

    const filtroEntregas = FiltroListagemEntregas(statusEntrega: 'todos');
    final entRes = deps.vendaRepository.carregarListagemEntregasComResumo(
      filtroLista: filtroEntregas,
      filtroContagem: filtroEntregas.paraContagemResumo(),
    );
    final emAberto = entRes.entregas
        .where((v) => !relatorioEntregaStatusFinalizado(v.statusEntrega))
        .length;

    deps.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final titulosAbertos = deps.vendaRepository.titulos.listarTodosAbertos();
    final totalAReceber = titulosAbertos.fold<double>(
      0,
      (s, l) => s + l.titulo.saldo,
    );
    final totalFiadoVencido = titulosAbertos
        .where(ContasReceberHelper.ehVencido)
        .fold<double>(0, (s, l) => s + l.titulo.saldo);

    final u = deps.usuarioLogado;
    final backupManual =
        await deps.appConfigRepository.carregarRegistroBackupManual();
    final backupStatus = BackupStatusHelper.avaliar(
      config: config,
      manual: backupManual,
    );
    final alertas = DashboardAlertasService.montar(
      vendaRepository: deps.vendaRepository,
      produtoRepository: deps.produtoRepository,
      objectBox: deps.objectBox,
      podeFinanceiro: UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro),
      podeEstoque: UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque),
      podeEntregas: UsuarioPermissaoHelper.podeVisualizarEntregas(u),
      empresaConfig: config,
      backupManual: backupManual,
      podeConfiguracoes: UsuarioPermissaoHelper.tem(
        u,
        PermissaoUsuario.configuracoes,
      ),
    );

    final fiscalPendencias = FiscalPendenciasResumoService.contar(
      vendaRepository: deps.vendaRepository,
    ).total;

    if (!mounted) return;
    setState(() {
      _config = config;
      _resumo = _MainMenuResumo(
        vendasHoje: vendas.length,
        faturamentoHoje: faturamento,
        caixaAberto: sessao.aberto,
        entregasEmAberto: emAberto,
        entregasAtrasadas: entRes.atrasadas,
        alertas: alertas,
        totalAReceber: totalAReceber,
        totalFiadoVencido: totalFiadoVencido,
        fiscalPendencias: fiscalPendencias,
        backupAlerta: backupStatus.exibirAlerta,
      );
      _carregandoResumo = false;
    });
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
      _ir(alerta.destino!);
    }
  }

  bool _tem(PermissaoUsuario p) =>
      UsuarioPermissaoHelper.tem(MainMenuDeps.of(context).usuarioLogado, p);

  void _ir(MainMenuDestino d) => MainMenuRouter.abrir(context, d);

  void _abrirLojaAoVivo() {
    final deps = MainMenuDeps.of(context);
    if (!UsuarioPermissaoHelper.tem(deps.usuarioLogado, PermissaoUsuario.vendasHub)) {
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
                  podeVendas: podeVendas,
                  podeCaixa: podeCaixa,
                  podeEntregas: podeEntregas,
                  podeFinanceiro: podeFinanceiro,
                ),
                if (podeVendas) ...[
                  const SizedBox(height: 12),
                  HubNavButton(
                    icon: Icons.monitor_heart_outlined,
                    corDestaque: AppModuloCores.modulo(
                      context,
                      AppModuloId.lojaAoVivo,
                    ),
                    titulo: 'Loja ao vivo',
                    subtitulo:
                        'Painel fullscreen: vendas/hora, caixa, entregas, estoque e metas.',
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
                const SizedBox(height: 16),
                const MainMenuSectionHeader(titulo: 'Fiscal e financeiro'),
                MainMenuTileGrid(
                  tiles: [
                    _tileModulo(MainMenuDestino.notasFiscais),
                    _tileModulo(MainMenuDestino.financeiro),
                  ],
                ),
                const SizedBox(height: 16),
                const MainMenuSectionHeader(titulo: 'Cadastros e sistema'),
                MainMenuTileGrid(
                  tiles: [
                    _tileModulo(MainMenuDestino.cadastros),
                    _tileModulo(MainMenuDestino.configuracoes),
                  ],
                ),
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
        title: Text(tituloAppBar),
        actions: [
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
    final badge = d == MainMenuDestino.notasFiscais
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
              rotulo: 'Vendas hoje',
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

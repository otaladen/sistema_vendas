import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/api/lan_api_client.dart';
import '../data/api/lan_api_event_hub.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/sync/caixa_status_hub.dart';
import '../data/sync/sync_refresh_hub.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/loja_ao_vivo_service.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../ui/relatorios/relatorio_horarios_pico_helper.dart';
import 'shell/app_shell_aba_visibilidade.dart';
import 'widgets/lan_api_feedback.dart';

/// Painel fullscreen com visao operacional da loja em tempo real.
class LojaAoVivoPage extends StatefulWidget {
  const LojaAoVivoPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    required this.usuarioLogado,
    this.objectBox,
    this.lanApiClient,
    this.terminalLeve = false,
  });

  final dynamic vendaRepository;
  final dynamic produtoRepository;
  final dynamic vendedorRepository;
  final ObjectBox? objectBox;
  final LanApiClient? lanApiClient;
  final bool terminalLeve;
  final UsuarioSistema usuarioLogado;

  @override
  State<LojaAoVivoPage> createState() => _LojaAoVivoPageState();
}

class _LojaAoVivoPageState extends State<LojaAoVivoPage> {
  final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final _horaFmt = DateFormat('HH:mm:ss');
  LojaAoVivoSnapshot? _snap;
  bool _carregando = true;
  Timer? _autoRefresh;
  bool _timerAtivo = false;
  VoidCallback? _syncHubListener;
  VoidCallback? _apiHubListener;
  VoidCallback? _caixaStatusListener;

  static const _entidades = {
    'venda',
    'entrega',
    'caixa',
    'caixa_sessoes',
    'titulo_receber',
    'produto',
  };

  bool get _viaApi =>
      widget.terminalLeve ||
      widget.objectBox == null ||
      widget.vendaRepository is! VendaRepository;

  @override
  void initState() {
    super.initState();
    _syncHubListener = () {
      if (!mounted || _viaApi) return;
      unawaited(_atualizar(silencioso: true));
    };
    SyncRefreshHub.instance.addListener(_syncHubListener!);
    _apiHubListener = () {
      if (!mounted || !_viaApi) return;
      final hub = LanApiEventHub.instance;
      if (!_entidades.contains(hub.ultimaEntidade)) return;
      unawaited(_atualizar(silencioso: true));
    };
    LanApiEventHub.instance.addListener(_apiHubListener!);
    _caixaStatusListener = () {
      if (!mounted) return;
      final snap = _snap;
      if (snap == null) return;
      final hub = CaixaStatusHub.instance;
      if (snap.caixaAberto == hub.lojaAberta &&
          snap.caixaOperador == hub.operador &&
          snap.caixaTerminalId == hub.terminalId) {
        return;
      }
      setState(() {
        _snap = LojaAoVivoSnapshot(
          vendasHoje: snap.vendasHoje,
          faturamentoHoje: snap.faturamentoHoje,
          horaPicoHoje: snap.horaPicoHoje,
          vendasHoraPico: snap.vendasHoraPico,
          caixaAberto: hub.lojaAberta,
          caixaOperador: hub.operador,
          caixaTerminalId: hub.terminalId,
          outroTerminalCaixaAberto: snap.outroTerminalCaixaAberto,
          entregasAtrasadas: snap.entregasAtrasadas,
          entregasEmAberto: snap.entregasEmAberto,
          estoqueCritico: snap.estoqueCritico,
          estoqueZerado: snap.estoqueZerado,
          fiadoVencido: snap.fiadoVencido,
          orcamentosAbertos: snap.orcamentosAbertos,
          metasVendedores: snap.metasVendedores,
          atualizadoEm: DateTime.now(),
        );
      });
    };
    CaixaStatusHub.instance.addListener(_caixaStatusListener!);
    unawaited(_atualizar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sincronizarTimerComVisibilidade();
  }

  bool _abaVisivelAgora() {
    if (!mounted) return false;
    final inherited =
        context.getInheritedWidgetOfExactType<AppShellAbaVisibilidade>();
    if (inherited != null && !inherited.ativa) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    return true;
  }

  void _sincronizarTimerComVisibilidade() {
    if (!mounted) return;
    // Sem Inherited do shell (rota push): considera visivel se rota atual.
    final inherited =
        context.getInheritedWidgetOfExactType<AppShellAbaVisibilidade>();
    final abaAtiva = inherited?.ativa ?? true;
    final route = ModalRoute.of(context);
    final deveRodar = abaAtiva && (route == null || route.isCurrent);
    if (deveRodar == _timerAtivo) return;
    final ficouVisivel = deveRodar && !_timerAtivo;
    _timerAtivo = deveRodar;
    _autoRefresh?.cancel();
    _autoRefresh = null;
    if (!deveRodar) return;
    if (ficouVisivel) unawaited(_atualizar(silencioso: true));
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_abaVisivelAgora()) return;
      unawaited(_atualizar(silencioso: true));
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    if (_syncHubListener != null) {
      SyncRefreshHub.instance.removeListener(_syncHubListener!);
    }
    if (_apiHubListener != null) {
      LanApiEventHub.instance.removeListener(_apiHubListener!);
    }
    if (_caixaStatusListener != null) {
      CaixaStatusHub.instance.removeListener(_caixaStatusListener!);
    }
    super.dispose();
  }

  Future<void> _atualizar({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() => _carregando = true);
    }
    try {
      LojaAoVivoSnapshot snap;
      final client = widget.lanApiClient;
      if (_viaApi && client != null && client.configurado) {
        final m = await client.obterLojaAoVivo(
          login: widget.usuarioLogado.login,
        );
        snap = LojaAoVivoSnapshot.fromMap(m);
        if (snap.caixaAberto) {
          CaixaStatusHub.instance.publicar(
            aberto: true,
            operador: snap.caixaOperador,
            terminalId: snap.caixaTerminalId,
          );
        } else if (!CaixaStatusHub.instance.lojaAberta) {
          CaixaStatusHub.instance.publicar(aberto: false);
        } else {
          // Hub local diz aberto: respeita (ex.: acabou de abrir neste PC).
          snap = LojaAoVivoSnapshot(
            vendasHoje: snap.vendasHoje,
            faturamentoHoje: snap.faturamentoHoje,
            horaPicoHoje: snap.horaPicoHoje,
            vendasHoraPico: snap.vendasHoraPico,
            caixaAberto: true,
            caixaOperador: CaixaStatusHub.instance.operador.isNotEmpty
                ? CaixaStatusHub.instance.operador
                : snap.caixaOperador,
            caixaTerminalId: CaixaStatusHub.instance.terminalId.isNotEmpty
                ? CaixaStatusHub.instance.terminalId
                : snap.caixaTerminalId,
            outroTerminalCaixaAberto: snap.outroTerminalCaixaAberto,
            entregasAtrasadas: snap.entregasAtrasadas,
            entregasEmAberto: snap.entregasEmAberto,
            estoqueCritico: snap.estoqueCritico,
            estoqueZerado: snap.estoqueZerado,
            fiadoVencido: snap.fiadoVencido,
            orcamentosAbertos: snap.orcamentosAbertos,
            metasVendedores: snap.metasVendedores,
            atualizadoEm: snap.atualizadoEm,
          );
        }
      } else if (widget.vendaRepository is VendaRepository &&
          widget.produtoRepository is ProdutoRepository &&
          widget.vendedorRepository is VendedorRepository) {
        snap = await LojaAoVivoService(
          vendaRepository: widget.vendaRepository as VendaRepository,
          produtoRepository: widget.produtoRepository as ProdutoRepository,
          vendedorRepository: widget.vendedorRepository as VendedorRepository,
          objectBox: widget.objectBox,
        ).carregar(usuario: widget.usuarioLogado);
      } else {
        throw StateError('Loja ao vivo: repositorios locais indisponiveis.');
      }
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      if (!silencioso) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Loja ao vivo');
      }
    }
  }

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = _snap;
    final u = widget.usuarioLogado;
    final verVendas = UsuarioPermissaoHelper.podeVerMinhasVendasHoje(u);
    final verCaixa = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
    final verEntregas = UsuarioPermissaoHelper.podeAcessarModuloEntregas(u);
    final verEstoque = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.estoque);
    final verFinanceiro =
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.financeiro);
    final verOrcamentos =
        UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u);
    final verMetasTodos =
        UsuarioPermissaoHelper.podeVerMetasVendedoresLoja(u);
    final verMetasProprias =
        !verMetasTodos && u.vendedorId > 0 && verVendas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loja ao vivo'),
        actions: [
          if (snap != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Atualizado ${_horaFmt.format(snap.atualizadoEm)}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => unawaited(_atualizar()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando && snap == null
          ? const Center(child: CircularProgressIndicator())
          : snap == null
              ? const Center(child: Text('Sem dados.'))
              : RefreshIndicator(
                  onRefresh: () => _atualizar(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (verVendas ||
                          verCaixa ||
                          verEntregas ||
                          verEstoque ||
                          verOrcamentos)
                        _buildGridKpis(
                          context,
                          snap,
                          verVendas: verVendas,
                          verCaixa: verCaixa,
                          verEntregas: verEntregas,
                          verEstoque: verEstoque,
                          verOrcamentos: verOrcamentos,
                          rotuloVendas:
                              UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(
                                    u,
                                  )
                                  ? 'Vendas hoje'
                                  : 'Minhas vendas hoje',
                        ),
                      if (verVendas ||
                          verCaixa ||
                          verEntregas ||
                          verEstoque ||
                          verOrcamentos)
                        const SizedBox(height: 16),
                      if (verCaixa && snap.outroTerminalCaixaAberto)
                        _buildAlerta(
                          context,
                          Icons.warning_amber_outlined,
                          'Outro terminal tem caixa aberto na rede. '
                          'Mantenha apenas um caixa aberto por loja.',
                          theme.colorScheme.errorContainer,
                        ),
                      if (verFinanceiro && snap.fiadoVencido > 0.001)
                        _buildAlerta(
                          context,
                          Icons.account_balance_wallet_outlined,
                          'Fiado vencido: ${_fmt(snap.fiadoVencido)}',
                          theme.colorScheme.errorContainer,
                        ),
                      if (verEstoque && snap.estoqueZerado > 0)
                        _buildAlerta(
                          context,
                          Icons.inventory_2_outlined,
                          '${snap.estoqueZerado} produto(s) com estoque zerado',
                          theme.colorScheme.tertiaryContainer,
                        ),
                      if (verEntregas && snap.entregasAtrasadas > 0)
                        _buildAlerta(
                          context,
                          Icons.local_shipping_outlined,
                          '${snap.entregasAtrasadas} entrega(s) atrasada(s)',
                          theme.colorScheme.secondaryContainer,
                        ),
                      if (verMetasTodos || verMetasProprias) ...[
                        const SizedBox(height: 8),
                        Text(
                          verMetasTodos
                              ? 'Metas dos vendedores (hoje)'
                              : 'Minha meta (hoje)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (snap.metasVendedores.isEmpty)
                          Text(
                            verMetasTodos
                                ? 'Nenhum vendedor com meta mensal cadastrada.'
                                : 'Nenhuma meta vinculada ao seu cadastro.',
                          )
                        else
                          ...snap.metasVendedores.map(
                            (m) => _buildMetaCard(context, m),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildAlerta(
    BuildContext context,
    IconData icon,
    String texto,
    Color bg,
  ) {
    return Card(
      color: bg,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(texto),
      ),
    );
  }

  Widget _buildGridKpis(
    BuildContext context,
    LojaAoVivoSnapshot snap, {
    required bool verVendas,
    required bool verCaixa,
    required bool verEntregas,
    required bool verEstoque,
    required bool verOrcamentos,
    required String rotuloVendas,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final cards = <Widget>[
          if (verVendas)
            _KpiCard(
              rotulo: rotuloVendas,
              valor: '${snap.vendasHoje}',
              detalhe: _fmt(snap.faturamentoHoje),
              icone: Icons.point_of_sale_outlined,
            ),
          if (verVendas)
            _KpiCard(
              rotulo: 'Pico do dia',
              valor: relatorioFormatarFaixaHoraria(snap.horaPicoHoje),
              detalhe: '${snap.vendasHoraPico} venda(s)',
              icone: Icons.schedule_outlined,
            ),
          if (verCaixa)
            _KpiCard(
              rotulo: 'Caixa',
              valor: snap.caixaAberto ? 'Aberto' : 'Fechado',
              detalhe: snap.caixaAberto
                  ? '${snap.caixaOperador} · ${snap.caixaTerminalId}'
                  : 'Nenhuma sessao aberta',
              icone: Icons.account_balance_outlined,
              destaque: snap.caixaAberto,
            ),
          if (verEntregas)
            _KpiCard(
              rotulo: 'Entregas',
              valor: '${snap.entregasEmAberto} abertas',
              detalhe: '${snap.entregasAtrasadas} atrasada(s)',
              icone: Icons.local_shipping_outlined,
              alerta: snap.entregasAtrasadas > 0,
            ),
          if (verEstoque)
            _KpiCard(
              rotulo: 'Estoque critico',
              valor: '${snap.estoqueCritico}',
              detalhe: '${snap.estoqueZerado} zerado(s)',
              icone: Icons.inventory_outlined,
              alerta: snap.estoqueCritico > 0 || snap.estoqueZerado > 0,
            ),
          if (verOrcamentos)
            _KpiCard(
              rotulo: 'Orcamentos',
              valor: '${snap.orcamentosAbertos}',
              detalhe: 'Aguardando caixa',
              icone: Icons.description_outlined,
            ),
        ];

        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: cols == 1 ? 3.2 : 1.55,
          children: cards,
        );
      },
    );
  }

  Widget _buildMetaCard(BuildContext context, MetaVendedorDiaria m) {
    final theme = Theme.of(context);
    final pct = (m.percentual * 100).clamp(0, 200);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.nome,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${pct.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: m.percentual.clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmt(m.realizadoHoje)} / ${_fmt(m.metaDiaria)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.rotulo,
    required this.valor,
    required this.detalhe,
    required this.icone,
    this.destaque = false,
    this.alerta = false,
  });

  final String rotulo;
  final String valor;
  final String detalhe;
  final IconData icone;
  final bool destaque;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = alerta
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
        : destaque
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    return Card(
      color: bg,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icone, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(rotulo, style: theme.textTheme.labelMedium),
                  Text(
                    valor,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(detalhe, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

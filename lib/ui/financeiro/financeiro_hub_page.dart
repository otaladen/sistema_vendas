import 'package:flutter/material.dart';

import '../../data/caixa_sessao_repository.dart';
import '../../data/cliente_repository.dart';
import '../../data/objectbox.dart';
import '../../data/venda_repository.dart';
import '../../domain/dashboard_alertas.dart';
import '../../domain/filtro_contas_pagar.dart';
import '../../domain/filtro_contas_receber.dart';
import '../../domain/financeiro_resumo.dart';
import '../../domain/main_menu_destino.dart';
import '../../domain/permissao_usuario.dart';
import '../../domain/usuario_permissao_helper.dart';
import '../../model/usuario_sistema.dart';
import '../relatorio_fiados_page.dart';
import '../shell/main_menu_router.dart';
import '../theme/app_modulo_cores.dart';
import '../widgets/conta_sessao_app_bar_actions.dart';
import '../widgets/dashboard_alertas_strip.dart';
import '../widgets/hub_nav_button.dart';
import 'contas_pagar_page.dart';
import 'contas_receber_page.dart';
import 'relatorio_contas_pagar_page.dart';
import 'tesouraria_semanal_page.dart';
import 'widgets/financeiro_resumo_painel.dart';

/// Hub do modulo Financeiro com painel executivo de tesouraria.
class FinanceiroHubPage extends StatefulWidget {
  const FinanceiroHubPage({
    super.key,
    required this.objectBox,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.usuarioLogado,
    required this.onLogout,
    this.filtroContasReceberInicial,
    this.filtroContasPagarInicial,
  });

  final ObjectBox objectBox;
  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final FiltroContasReceber? filtroContasReceberInicial;
  final FiltroContasPagar? filtroContasPagarInicial;

  @override
  State<FinanceiroHubPage> createState() => _FinanceiroHubPageState();
}

class _FinanceiroHubPageState extends State<FinanceiroHubPage> {
  FinanceiroResumoSnapshot? _resumo;
  List<DashboardAlerta> _alertas = const [];
  bool _carregando = true;
  String? _erroCarregamento;
  double? _saldoCaixaRef;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erroCarregamento = null;
    });
    try {
      final repo = CaixaSessaoRepository();
      final terminalId = await repo.obterTerminalId();
      final sessoes = await repo.listarTodasSessoes();
      final sessao = sessoes[terminalId];
      final double? saldo = sessao != null && sessao.aberto
          ? (sessao.fundoTroco + sessao.suprimentos - sessao.sangrias)
              .clamp(0, double.infinity)
              .toDouble()
          : null;

      final resumo = FinanceiroResumoService.montar(
        vendaRepository: widget.vendaRepository,
        objectBox: widget.objectBox,
        sessaoCaixaLocal: sessao,
      );

      final alertas = <DashboardAlerta>[];
      if (resumo.aReceberVencido > 0.01) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.fiadoVencido,
            titulo: 'Fiado vencido',
            detalhe:
                '${resumo.qtdTitulosReceberAbertos} titulo(s) · R\$ ${_fmt(resumo.aReceberVencido)}',
            icone: Icons.warning_amber_rounded,
            filtroContasReceber: FiltroContasReceber.vencidos,
            prioridade: 10,
          ),
        );
      }
      if (resumo.aReceberVenceHoje > 0.01) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.fiadoVenceHoje,
            titulo: 'Fiado vence hoje',
            detalhe: 'R\$ ${_fmt(resumo.aReceberVenceHoje)}',
            icone: Icons.schedule_outlined,
            filtroContasReceber: FiltroContasReceber.venceHoje,
            prioridade: 20,
          ),
        );
      }
      if (resumo.qtdContasPagarAtrasadas > 0) {
        alertas.add(
          DashboardAlerta(
            tipo: DashboardAlertaTipo.contaPagarVencida,
            titulo: 'Contas a pagar vencidas',
            detalhe:
                '${resumo.qtdContasPagarAtrasadas} parcela(s) · R\$ ${_fmt(resumo.aPagarAtrasado)}',
            icone: Icons.account_balance_outlined,
            filtroContasPagar: FiltroContasPagar.atrasados,
            prioridade: 25,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _resumo = resumo;
        _saldoCaixaRef = saldo;
        _alertas = alertas;
        _carregando = false;
        _erroCarregamento = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroCarregamento = e.toString();
      });
    }
  }

  bool get _podeFinanceiro =>
      UsuarioPermissaoHelper.tem(widget.usuarioLogado, PermissaoUsuario.financeiro);

  bool get _podeCaixa =>
      UsuarioPermissaoHelper.tem(widget.usuarioLogado, PermissaoUsuario.acessarCaixa);

  bool get _podeRelatorioFiado =>
      UsuarioPermissaoHelper.tem(widget.usuarioLogado, PermissaoUsuario.relatoriosFiado);

  void _abrirCaixa() {
    MainMenuRouter.abrir(context, MainMenuDestino.caixa);
  }

  void _abrirReceber({FiltroContasReceber filtro = FiltroContasReceber.todos}) {
    if (!_podeFinanceiro) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContasReceberPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
          usuarioLogado: widget.usuarioLogado,
          podeRegistrarRecebimento: _podeCaixa,
          filtroInicial: filtro,
        ),
      ),
    ).then((_) => _carregar());
  }

  void _abrirPagar({FiltroContasPagar filtro = FiltroContasPagar.todos}) {
    if (!_podeFinanceiro) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContasPagarPage(
          objectBox: widget.objectBox,
          saldoCaixaReferencia: _saldoCaixaRef,
          filtroInicial: filtro,
        ),
      ),
    ).then((_) => _carregar());
  }

  void _abrirRelatorioContasPagar() {
    if (!_podeFinanceiro) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelatorioContasPagarPage(objectBox: widget.objectBox),
      ),
    );
  }

  void _abrirTesourariaSemanal() {
    if (!_podeFinanceiro) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TesourariaSemanalPage(
          objectBox: widget.objectBox,
          vendaRepository: widget.vendaRepository,
        ),
      ),
    ).then((_) => _carregar());
  }

  void _abrirRelatorioFiados() {
    if (!_podeRelatorioFiado) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelatorioFiadosPage(
          vendaRepository: widget.vendaRepository,
          clienteRepository: widget.clienteRepository,
        ),
      ),
    );
  }

  void _onAlertaTap(DashboardAlerta alerta) {
    if (alerta.filtroContasReceber != null) {
      _abrirReceber(filtro: alerta.filtroContasReceber!);
      return;
    }
    if (alerta.filtroContasPagar != null) {
      _abrirPagar(filtro: alerta.filtroContasPagar!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filtroContasReceberInicial != null && _podeFinanceiro) {
      return ContasReceberPage(
        vendaRepository: widget.vendaRepository,
        clienteRepository: widget.clienteRepository,
        usuarioLogado: widget.usuarioLogado,
        podeRegistrarRecebimento: _podeCaixa,
        filtroInicial: widget.filtroContasReceberInicial!,
      );
    }
    if (widget.filtroContasPagarInicial != null && _podeFinanceiro) {
      return ContasPagarPage(
        objectBox: widget.objectBox,
        saldoCaixaReferencia: _saldoCaixaRef,
        filtroInicial: widget.filtroContasPagarInicial!,
      );
    }

    final resumo = _resumo;
    final operacao = _buildModulosOperacao(resumo);
    final relatorios = _buildModulosRelatorios(resumo);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _carregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
          ContaSessaoAppBarActions(
            login: widget.usuarioLogado.login,
            onLogout: widget.onLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 960;
            final maxW = desktop ? 1100.0 : 720.0;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: desktop
                      ? _buildLayoutDesktop(
                          resumo: resumo,
                          operacao: operacao,
                          relatorios: relatorios,
                        )
                      : _buildLayoutMobile(
                          resumo: resumo,
                          operacao: operacao,
                          relatorios: relatorios,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLayoutMobile({
    required FinanceiroResumoSnapshot? resumo,
    required List<Widget> operacao,
    required List<Widget> relatorios,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FinanceiroHeroHeader(resumo: resumo, carregando: _carregando),
        const SizedBox(height: 12),
        _buildAtalhosRapidos(resumo),
        const SizedBox(height: 16),
        _buildPainelPrincipal(resumo),
        const SizedBox(height: 20),
        _FinanceiroHubSecao(
          titulo: 'Operacao',
          icone: Icons.account_balance_wallet_outlined,
          quantidadeItens: operacao.length,
        ),
        ...operacao,
        const SizedBox(height: 8),
        _FinanceiroHubSecao(
          titulo: 'Relatorios',
          icone: Icons.summarize_outlined,
          quantidadeItens: relatorios.length,
        ),
        ...relatorios,
        if (!_podeCaixa && _podeFinanceiro) ...[
          const SizedBox(height: 16),
          _cardInfoRecebimento(),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLayoutDesktop({
    required FinanceiroResumoSnapshot? resumo,
    required List<Widget> operacao,
    required List<Widget> relatorios,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FinanceiroHeroHeader(resumo: resumo, carregando: _carregando),
        const SizedBox(height: 12),
        _buildAtalhosRapidos(resumo),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPainelPrincipal(resumo),
                  if (!_podeCaixa && _podeFinanceiro) ...[
                    const SizedBox(height: 16),
                    _cardInfoRecebimento(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 4,
              child: Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FinanceiroHubSecao(
                        titulo: 'Operacao',
                        icone: Icons.account_balance_wallet_outlined,
                        quantidadeItens: operacao.length,
                      ),
                      ...operacao,
                      const SizedBox(height: 4),
                      _FinanceiroHubSecao(
                        titulo: 'Relatorios',
                        icone: Icons.summarize_outlined,
                        quantidadeItens: relatorios.length,
                      ),
                      ...relatorios,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPainelPrincipal(FinanceiroResumoSnapshot? resumo) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_erroCarregamento != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nao foi possivel carregar o financeiro',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(_erroCarregamento!),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _carregar,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (resumo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceiroResumoPainel(
          resumo: resumo,
          onTapAReceber: () => _abrirReceber(),
          onTapAReceberVencido: () =>
              _abrirReceber(filtro: FiltroContasReceber.vencidos),
          onTapAPagar: () => _abrirPagar(),
          onTapAPagarAtrasado: () =>
              _abrirPagar(filtro: FiltroContasPagar.atrasados),
          onTapSaldoProjetado: _abrirTesourariaSemanal,
        ),
        if (_alertas.isNotEmpty) ...[
          const SizedBox(height: 16),
          _FinanceiroHubSecao(
            titulo: 'Alertas',
            icone: Icons.notifications_active_outlined,
            quantidadeItens: _alertas.length,
          ),
          DashboardAlertasStrip(
            alertas: _alertas,
            onAlertaTap: _onAlertaTap,
          ),
        ],
      ],
    );
  }

  Widget _buildAtalhosRapidos(FinanceiroResumoSnapshot? resumo) {
    final corCaixa = MainMenuDestino.caixa.cor(context);
    final chips = <Widget>[];

    if (_podeCaixa) {
      chips.add(
        FilledButton.tonalIcon(
          onPressed: _abrirCaixa,
          icon: const Icon(Icons.point_of_sale_outlined, size: 18),
          label: Text(
            resumo?.caixaAberto == true ? 'Caixa aberto' : 'Ir ao Caixa',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: corCaixa.withValues(alpha: 0.12),
            foregroundColor: corCaixa,
          ),
        ),
      );
    }
    if (_podeFinanceiro) {
      chips.add(
        OutlinedButton.icon(
          onPressed: _abrirTesourariaSemanal,
          icon: const Icon(Icons.calendar_view_week_outlined, size: 18),
          label: const Text('Tesouraria 7 dias'),
        ),
      );
      if (resumo != null && resumo.aReceberVencido > 0.01) {
        chips.add(
          OutlinedButton.icon(
            onPressed: () => _abrirReceber(filtro: FiltroContasReceber.vencidos),
            icon: const Icon(Icons.warning_amber_rounded, size: 18),
            label: Text('Fiado vencido · R\$ ${_fmt(resumo.aReceberVencido)}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppModuloCores.alerta(
                context,
                DashboardAlertaTipo.fiadoVencido,
              ),
            ),
          ),
        );
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _cardInfoRecebimento() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: Icon(
          Icons.info_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Recebimento de fiado'),
        subtitle: const Text(
          'Para registrar recebimentos, use o Caixa (permissao de operador). '
          'Aqui voce acompanha titulos e inadimplencia.',
        ),
      ),
    );
  }

  List<Widget> _buildModulosOperacao(FinanceiroResumoSnapshot? resumo) {
    final botoes = <Widget>[
      HubNavButton(
        icon: Icons.calendar_view_week_outlined,
        corDestaque: AppModuloCores.modulo(context, AppModuloId.tesouraria),
        titulo: 'Tesouraria semanal',
        subtitulo: resumo != null
            ? 'Previsto 7d: R\$ ${_fmt(resumo.aReceberProximos7)} receber · R\$ ${_fmt(resumo.aPagarProximos7)} pagar'
            : 'Vencimentos e movimentos da semana',
        habilitado: _podeFinanceiro,
        onTap: _abrirTesourariaSemanal,
      ),
      HubNavButton(
        icon: Icons.call_received_outlined,
        corDestaque: AppModuloCores.modulo(context, AppModuloId.contasReceber),
        titulo: 'Contas a receber',
        subtitulo: resumo != null
            ? '${resumo.qtdTitulosReceberAbertos} titulo(s) · R\$ ${_fmt(resumo.totalAReceber)}'
            : 'Fiado, vencidos e recebimentos',
        habilitado: _podeFinanceiro,
        onTap: () => _abrirReceber(),
      ),
      HubNavButton(
        icon: Icons.call_made_outlined,
        corDestaque: AppModuloCores.modulo(context, AppModuloId.contasPagar),
        titulo: 'Contas a pagar',
        subtitulo: resumo != null
            ? '${resumo.qtdContasPagarAbertas} parcela(s) · R\$ ${_fmt(resumo.totalAPagarPendente)}'
            : 'Fornecedores, NF-e e despesas',
        habilitado: _podeFinanceiro,
        onTap: () => _abrirPagar(),
      ),
    ];

    return _espacarBotoes(botoes);
  }

  List<Widget> _buildModulosRelatorios(FinanceiroResumoSnapshot? resumo) {
    final botoes = <Widget>[
      HubNavButton(
        icon: Icons.receipt_long_outlined,
        corDestaque: AppModuloCores.modulo(context, AppModuloId.relatorioContasPagar),
        titulo: 'Relatorio contas a pagar',
        subtitulo: 'PDF, CSV e agrupamento por fornecedor',
        habilitado: _podeFinanceiro,
        onTap: _abrirRelatorioContasPagar,
      ),
      HubNavButton(
        icon: Icons.assessment_outlined,
        corDestaque: AppModuloCores.modulo(context, AppModuloId.relatorioFiados),
        titulo: 'Relatorio de fiados',
        subtitulo: 'Exportar CSV/PDF, agrupar por cliente',
        habilitado: _podeRelatorioFiado,
        onTap: _abrirRelatorioFiados,
      ),
    ];

    return _espacarBotoes(botoes);
  }

  List<Widget> _espacarBotoes(List<Widget> botoes) {
    return [
      for (var i = 0; i < botoes.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        botoes[i],
      ],
    ];
  }

  String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}

class _FinanceiroHeroHeader extends StatelessWidget {
  const _FinanceiroHeroHeader({
    required this.resumo,
    required this.carregando,
  });

  final FinanceiroResumoSnapshot? resumo;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.payments_outlined, color: scheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financeiro e tesouraria',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                if (carregando)
                  Text(
                    'Atualizando indicadores...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else if (resumo != null)
                  Text(
                    resumo!.temAlertaCritico
                        ? 'Atencao: existem titulos vencidos ou atrasados.'
                        : resumo!.semMovimentacaoFinanceira
                            ? 'Situacao tranquila — nenhum titulo em aberto.'
                            : 'Acompanhe recebimentos, pagamentos e saldo projetado.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceiroHubSecao extends StatelessWidget {
  const _FinanceiroHubSecao({
    required this.titulo,
    required this.icone,
    this.quantidadeItens,
  });

  final String titulo;
  final IconData icone;
  final int? quantidadeItens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Icon(icone, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (quantidadeItens != null)
            Text(
              '$quantidadeItens',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

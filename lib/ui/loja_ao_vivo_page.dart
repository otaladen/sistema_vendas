import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/loja_ao_vivo_service.dart';
import '../ui/relatorios/relatorio_horarios_pico_helper.dart';

/// Painel fullscreen com visao operacional da loja em tempo real.
class LojaAoVivoPage extends StatefulWidget {
  const LojaAoVivoPage({
    super.key,
    required this.vendaRepository,
    required this.produtoRepository,
    required this.vendedorRepository,
    required this.objectBox,
  });

  final VendaRepository vendaRepository;
  final ProdutoRepository produtoRepository;
  final VendedorRepository vendedorRepository;
  final ObjectBox objectBox;

  @override
  State<LojaAoVivoPage> createState() => _LojaAoVivoPageState();
}

class _LojaAoVivoPageState extends State<LojaAoVivoPage> {
  final _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final _horaFmt = DateFormat('HH:mm:ss');
  LojaAoVivoSnapshot? _snap;
  bool _carregando = true;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _atualizar();
    _autoRefresh = Timer.periodic(const Duration(seconds: 30), (_) => _atualizar());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _atualizar() async {
    setState(() => _carregando = true);
    final svc = LojaAoVivoService(
      vendaRepository: widget.vendaRepository,
      produtoRepository: widget.produtoRepository,
      vendedorRepository: widget.vendedorRepository,
      objectBox: widget.objectBox,
    );
    final snap = await svc.carregar();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _carregando = false;
    });
  }

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = _snap;

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
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _carregando && snap == null
          ? const Center(child: CircularProgressIndicator())
          : snap == null
              ? const Center(child: Text('Sem dados.'))
              : RefreshIndicator(
                  onRefresh: _atualizar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildGridKpis(context, snap),
                      const SizedBox(height: 16),
                      if (snap.outroTerminalCaixaAberto)
                        _buildAlerta(
                          context,
                          Icons.warning_amber_outlined,
                          'Outro terminal tem caixa aberto na rede. '
                          'Mantenha apenas um caixa aberto por loja.',
                          theme.colorScheme.errorContainer,
                        ),
                      if (snap.fiadoVencido > 0.001)
                        _buildAlerta(
                          context,
                          Icons.account_balance_wallet_outlined,
                          'Fiado vencido: ${_fmt(snap.fiadoVencido)}',
                          theme.colorScheme.errorContainer,
                        ),
                      if (snap.estoqueZerado > 0)
                        _buildAlerta(
                          context,
                          Icons.inventory_2_outlined,
                          '${snap.estoqueZerado} produto(s) com estoque zerado',
                          theme.colorScheme.tertiaryContainer,
                        ),
                      if (snap.entregasAtrasadas > 0)
                        _buildAlerta(
                          context,
                          Icons.local_shipping_outlined,
                          '${snap.entregasAtrasadas} entrega(s) atrasada(s)',
                          theme.colorScheme.secondaryContainer,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Metas dos vendedores (hoje)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (snap.metasVendedores.isEmpty)
                        const Text('Nenhum vendedor com meta mensal cadastrada.')
                      else
                        ...snap.metasVendedores.map(
                          (m) => _buildMetaCard(context, m),
                        ),
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

  Widget _buildGridKpis(BuildContext context, LojaAoVivoSnapshot snap) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final cards = [
          _KpiCard(
            rotulo: 'Vendas hoje',
            valor: '${snap.vendasHoje}',
            detalhe: _fmt(snap.faturamentoHoje),
            icone: Icons.point_of_sale_outlined,
          ),
          _KpiCard(
            rotulo: 'Pico do dia',
            valor: relatorioFormatarFaixaHoraria(snap.horaPicoHoje),
            detalhe: '${snap.vendasHoraPico} venda(s)',
            icone: Icons.schedule_outlined,
          ),
          _KpiCard(
            rotulo: 'Caixa',
            valor: snap.caixaAberto ? 'Aberto' : 'Fechado',
            detalhe: snap.caixaAberto
                ? '${snap.caixaOperador} · ${snap.caixaTerminalId}'
                : 'Nenhuma sessao local',
            icone: Icons.account_balance_outlined,
            destaque: snap.caixaAberto,
          ),
          _KpiCard(
            rotulo: 'Entregas',
            valor: '${snap.entregasEmAberto} abertas',
            detalhe: '${snap.entregasAtrasadas} atrasada(s)',
            icone: Icons.local_shipping_outlined,
            alerta: snap.entregasAtrasadas > 0,
          ),
          _KpiCard(
            rotulo: 'Estoque critico',
            valor: '${snap.estoqueCritico}',
            detalhe: '${snap.estoqueZerado} zerado(s)',
            icone: Icons.inventory_outlined,
            alerta: snap.estoqueCritico > 0 || snap.estoqueZerado > 0,
          ),
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
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols >= 4 ? 1.55 : 1.85,
          children: cards,
        );
      },
    );
  }

  Widget _buildMetaCard(BuildContext context, MetaVendedorDiaria m) {
    final pct = (m.percentual * 100).clamp(0, 200);
    final theme = Theme.of(context);
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: pct >= 100
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: m.percentual > 1 ? 1 : m.percentual,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              'Hoje: ${_fmt(m.realizadoHoje)} · Meta dia: ${_fmt(m.metaDiaria)}',
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
    final scheme = theme.colorScheme;
    return Card(
      color: alerta
          ? scheme.errorContainer.withValues(alpha: 0.35)
          : destaque
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 20, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    rotulo,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              valor,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              detalhe,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

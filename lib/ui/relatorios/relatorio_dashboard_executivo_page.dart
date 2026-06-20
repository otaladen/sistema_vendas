import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_periodo.dart';
import '../theme/app_relatorio_cores.dart';

class RelatorioDashboardExecutivoPage extends StatefulWidget {
  const RelatorioDashboardExecutivoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioDashboardExecutivoPage> createState() =>
      _RelatorioDashboardExecutivoPageState();
}

class _RelatorioDashboardExecutivoPageState
    extends State<RelatorioDashboardExecutivoPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  Widget build(BuildContext context) {
    final mesAtual = calcularLimitesPeriodo(preset: 'mes_atual');
    final mesAnt = relatorioPeriodoAnterior(mesAtual);
    final totAtual = relatorioTotaisPeriodo(widget.vendaRepository, mesAtual);
    final totAnt = relatorioTotaisPeriodo(widget.vendaRepository, mesAnt);

    final titulosVencidos = widget.vendaRepository.titulos
        .listarTodosAbertos(somenteVencidos: true);
    final saldoFiadoVencido =
        titulosVencidos.fold<double>(0, (s, l) => s + l.titulo.saldo);

    final estoqueCritico = widget.produtoRepository.listarTodos().where(
          (p) => p.estoqueReal < p.quantidadeMinima,
        );
    final orcs = widget.vendaRepository.listarOrcamentosPendentes();
    final hoje = DateTime.now();
    final orcsAntigos = orcs.where((v) {
      final d = v.data.toLocal();
      final ref = DateTime(hoje.year, hoje.month, hoje.day);
      final vd = DateTime(d.year, d.month, d.day);
      return ref.difference(vd).inDays >= 7;
    }).length;

    final entregas = widget.vendaRepository.listarEntregas();
    final entAtrasadas =
        entregas.where(relatorioEntregaEhAtrasada).length;
    final entHoje = entregas.where(relatorioEntregaEhAgendaHoje).length;

    final linhasPromoMes = widget.vendaRepository.listarVendasPromocaoPeriodo(
      inicio: mesAtual.$1,
      fim: mesAtual.$2,
    );
    final totalPromoMes =
        linhasPromoMes.fold<double>(0, (s, l) => s + l.total);
    final campanhasMes =
        linhasPromoMes.map((l) => l.promocaoId).toSet().length;

    return Scaffold(
      appBar: AppBar(title: const Text('Painel executivo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mes atual (${formatarIntervaloPeriodo(mesAtual)})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RelatorioKpiComparativo(
            atual: totAtual,
            anterior: totAnt,
            formatarMoeda: _fmt,
            mostrarComparativo: true,
          ),
          const SizedBox(height: 6),
          Text(
            'vs periodo anterior (${formatarIntervaloPeriodo(mesAnt)})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.local_offer,
                color: AppRelatorioCores.cor(
                  context,
                  AppRelatorioId.vendasPromocao,
                ),
              ),
              title: const Text(
                'Vendas em promocao (mes)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                linhasPromoMes.isEmpty
                    ? 'Nenhuma linha promocional no periodo.'
                    : '${linhasPromoMes.length} linha(s) · '
                        '$campanhasMes campanha(s) · total ${_fmt(totalPromoMes)}',
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Alertas operacionais',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _alertaCard(
            context,
            icon: Icons.receipt_long_outlined,
            cor: Colors.red.shade700,
            titulo: 'Fiados vencidos',
            valor: '${titulosVencidos.length} titulo(s)',
            subtitulo: 'Saldo ${_fmt(saldoFiadoVencido)}',
            critico: titulosVencidos.isNotEmpty,
          ),
          _alertaCard(
            context,
            icon: Icons.warning_amber_outlined,
            cor: Colors.orange.shade800,
            titulo: 'Estoque abaixo do minimo',
            valor: '${estoqueCritico.length} produto(s)',
            critico: estoqueCritico.isNotEmpty,
          ),
          _alertaCard(
            context,
            icon: Icons.description_outlined,
            cor: Colors.indigo,
            titulo: 'Orcamentos parados (7+ dias)',
            valor: '$orcsAntigos de ${orcs.length}',
            critico: orcsAntigos > 0,
          ),
          _alertaCard(
            context,
            icon: Icons.local_shipping_outlined,
            cor: Colors.blue.shade700,
            titulo: 'Entregas',
            valor: '$entAtrasadas atrasada(s) · $entHoje para hoje',
            critico: entAtrasadas > 0,
          ),
          const SizedBox(height: 12),
          Text(
            'Regra ABC: classe A ate 80% do faturamento acumulado, B ate 95%, C restante.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _alertaCard(
    BuildContext context, {
    required IconData icon,
    required Color cor,
    required String titulo,
    required String valor,
    String? subtitulo,
    bool critico = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: critico
          ? cor.withValues(alpha: 0.08)
          : null,
      child: ListTile(
        leading: Icon(icon, color: cor),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitulo != null
            ? Text('$valor\n$subtitulo')
            : Text(valor),
        isThreeLine: subtitulo != null,
      ),
    );
  }
}

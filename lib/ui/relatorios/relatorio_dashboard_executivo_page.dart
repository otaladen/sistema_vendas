import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../data/titulo_receber_repository.dart';
import '../../data/venda_repository.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../widgets/lan_api_feedback.dart';
import 'relatorio_comparativo.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_export_util.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import '../theme/app_relatorio_cores.dart';

class _PainelExecutivoSnap {
  const _PainelExecutivoSnap({
    required this.mesAtual,
    required this.mesAnt,
    required this.totAtual,
    required this.totAnt,
    required this.qtdFiadosVencidos,
    required this.saldoFiadoVencido,
    required this.qtdEstoqueCritico,
    required this.qtdOrcs,
    required this.qtdOrcsAntigos,
    required this.entAtrasadas,
    required this.entHoje,
    required this.qtdLinhasPromo,
    required this.campanhasMes,
    required this.totalPromoMes,
  });

  final LimitesPeriodo mesAtual;
  final LimitesPeriodo mesAnt;
  final RelatorioTotaisPeriodo totAtual;
  final RelatorioTotaisPeriodo totAnt;
  final int qtdFiadosVencidos;
  final double saldoFiadoVencido;
  final int qtdEstoqueCritico;
  final int qtdOrcs;
  final int qtdOrcsAntigos;
  final int entAtrasadas;
  final int entHoje;
  final int qtdLinhasPromo;
  final int campanhasMes;
  final double totalPromoMes;
}

class RelatorioDashboardExecutivoPage extends StatefulWidget {
  const RelatorioDashboardExecutivoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.produtoRepository,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic produtoRepository;

  @override
  State<RelatorioDashboardExecutivoPage> createState() =>
      _RelatorioDashboardExecutivoPageState();
}

class _RelatorioDashboardExecutivoPageState
    extends State<RelatorioDashboardExecutivoPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  bool _carregando = true;

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        final mes = calcularLimitesPeriodo(preset: 'mes_atual');
        final ant = relatorioPeriodoAnterior(mes);
        await Future.wait([
          repo.garantirPeriodoRelatorioCarregado(ant.$1, mes.$2),
          repo.hidratarOrcamentos(limit: 200),
          repo.hidratarEntregas(limit: 500),
          repo.hidratarTitulos(),
        ]);
      } catch (e) {
        if (mounted) {
          LanApiFeedback.snackAviso(context, e, prefixo: 'Painel');
        }
      }
    }
    if (mounted) setState(() => _carregando = false);
  }

  _PainelExecutivoSnap _snap() {
    final mesAtual = calcularLimitesPeriodo(preset: 'mes_atual');
    final mesAnt = relatorioPeriodoAnterior(mesAtual);
    final totAtual = relatorioTotaisPeriodo(widget.vendaRepository, mesAtual);
    final totAnt = relatorioTotaisPeriodo(widget.vendaRepository, mesAnt);

    final titulosVencidos =
        (widget.vendaRepository.titulos.listarTodosAbertos(somenteVencidos: true)
                as List)
            .cast<TituloReceberResumoLinha>();
    final saldoFiadoVencido =
        titulosVencidos.fold<double>(0, (s, l) => s + l.titulo.saldo);

    final estoqueCritico = (widget.produtoRepository.listarTodos() as List)
        .cast<Produto>()
        .where(
          (p) => p.estoqueExibicao < p.quantidadeMinima,
        )
        .length;
    final orcs = (widget.vendaRepository.listarOrcamentosPendentes() as List)
        .cast<Venda>();
    final hoje = DateTime.now();
    final orcsAntigos = orcs.where((v) {
      final d = v.data.toLocal();
      final ref = DateTime(hoje.year, hoje.month, hoje.day);
      final vd = DateTime(d.year, d.month, d.day);
      return ref.difference(vd).inDays >= 7;
    }).length;

    final entregas =
        (widget.vendaRepository.listarEntregas() as List).cast<Venda>();
    final entAtrasadas = entregas.where(relatorioEntregaEhAtrasada).length;
    final entHoje = entregas.where(relatorioEntregaEhAgendaHoje).length;

    final linhasPromoMes =
        (widget.vendaRepository.listarVendasPromocaoPeriodo(
              inicio: mesAtual.$1,
              fim: mesAtual.$2,
            ) as List)
            .cast<VendaPromocaoRelatorioLinha>();
    final totalPromoMes = linhasPromoMes.fold<double>(0, (s, l) => s + l.total);
    final campanhasMes = linhasPromoMes.map((l) => l.promocaoId).toSet().length;

    return _PainelExecutivoSnap(
      mesAtual: mesAtual,
      mesAnt: mesAnt,
      totAtual: totAtual,
      totAnt: totAnt,
      qtdFiadosVencidos: titulosVencidos.length,
      saldoFiadoVencido: saldoFiadoVencido,
      qtdEstoqueCritico: estoqueCritico,
      qtdOrcs: orcs.length,
      qtdOrcsAntigos: orcsAntigos,
      entAtrasadas: entAtrasadas,
      entHoje: entHoje,
      qtdLinhasPromo: linhasPromoMes.length,
      campanhasMes: campanhasMes,
      totalPromoMes: totalPromoMes,
    );
  }

  List<List<String>> _linhasCsv() {
    final s = _snap();
    return [
      ['Indicador', 'Valor'],
      ['Periodo', formatarIntervaloPeriodo(s.mesAtual)],
      ['Faturamento', _moeda.format(s.totAtual.faturamento)],
      ['Lucro', _moeda.format(s.totAtual.lucro)],
      ['Notas', '${s.totAtual.qtdNotas}'],
      ['Ticket medio', _moeda.format(s.totAtual.ticketMedio)],
      ['Margem %', s.totAtual.margemPct.toStringAsFixed(1)],
      ['Faturamento mes anterior', _moeda.format(s.totAnt.faturamento)],
      ['Lucro mes anterior', _moeda.format(s.totAnt.lucro)],
      ['Promocao linhas', '${s.qtdLinhasPromo}'],
      ['Promocao campanhas', '${s.campanhasMes}'],
      ['Promocao total', _moeda.format(s.totalPromoMes)],
      ['Fiados vencidos', '${s.qtdFiadosVencidos}'],
      ['Saldo fiado vencido', _moeda.format(s.saldoFiadoVencido)],
      ['Estoque abaixo do minimo', '${s.qtdEstoqueCritico}'],
      ['Orcamentos parados 7+ dias', '${s.qtdOrcsAntigos}'],
      ['Orcamentos abertos', '${s.qtdOrcs}'],
      ['Entregas atrasadas', '${s.entAtrasadas}'],
      ['Entregas hoje', '${s.entHoje}'],
    ];
  }

  List<String> _paginasPdf() {
    final s = _snap();
    return relatorioMontarPaginasTabela(
      titulo: 'PAINEL EXECUTIVO',
      subtitulo: formatarIntervaloPeriodo(s.mesAtual),
      cabecalho: ['Indicador', 'Valor'],
      linhas: [
        ['Faturamento', _fmt(s.totAtual.faturamento)],
        ['Lucro', _fmt(s.totAtual.lucro)],
        ['Notas', '${s.totAtual.qtdNotas}'],
        ['Ticket medio', _fmt(s.totAtual.ticketMedio)],
        ['Margem', '${s.totAtual.margemPct.toStringAsFixed(1)}%'],
        ['vs mes anterior fat.', _fmt(s.totAnt.faturamento)],
        ['Promocao (mes)', _fmt(s.totalPromoMes)],
        ['Fiados vencidos', '${s.qtdFiadosVencidos} · ${_fmt(s.saldoFiadoVencido)}'],
        ['Estoque abaixo do minimo', '${s.qtdEstoqueCritico}'],
        ['Orcamentos 7+ dias', '${s.qtdOrcsAntigos} de ${s.qtdOrcs}'],
        ['Entregas', '${s.entAtrasadas} atrasada(s) · ${s.entHoje} hoje'],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel executivo')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final s = _snap();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel executivo'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'painel_executivo',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mes atual (${formatarIntervaloPeriodo(s.mesAtual)})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RelatorioKpiComparativo(
            atual: s.totAtual,
            anterior: s.totAnt,
            formatarMoeda: _fmt,
            mostrarComparativo: true,
          ),
          const SizedBox(height: 6),
          Text(
            'vs periodo anterior (${formatarIntervaloPeriodo(s.mesAnt)})',
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
                s.qtdLinhasPromo == 0
                    ? 'Nenhuma linha promocional no periodo.'
                    : '${s.qtdLinhasPromo} linha(s) · '
                        '${s.campanhasMes} campanha(s) · total ${_fmt(s.totalPromoMes)}',
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
            valor: '${s.qtdFiadosVencidos} titulo(s)',
            subtitulo: 'Saldo ${_fmt(s.saldoFiadoVencido)}',
            critico: s.qtdFiadosVencidos > 0,
          ),
          _alertaCard(
            context,
            icon: Icons.warning_amber_outlined,
            cor: Colors.orange.shade800,
            titulo: 'Estoque abaixo do minimo',
            valor: '${s.qtdEstoqueCritico} produto(s)',
            critico: s.qtdEstoqueCritico > 0,
          ),
          _alertaCard(
            context,
            icon: Icons.description_outlined,
            cor: Colors.indigo,
            titulo: 'Orcamentos parados (7+ dias)',
            valor: '${s.qtdOrcsAntigos} de ${s.qtdOrcs}',
            critico: s.qtdOrcsAntigos > 0,
          ),
          _alertaCard(
            context,
            icon: Icons.local_shipping_outlined,
            cor: Colors.blue.shade700,
            titulo: 'Entregas',
            valor: '${s.entAtrasadas} atrasada(s) · ${s.entHoje} para hoje',
            critico: s.entAtrasadas > 0,
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
      color: critico ? cor.withValues(alpha: 0.08) : null,
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

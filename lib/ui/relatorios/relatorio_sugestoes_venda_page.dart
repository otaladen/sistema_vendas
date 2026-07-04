import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/produto_repository.dart';
import '../../data/sugestao_venda_metrica_repository.dart';
import '../../domain/sugestao_venda_metrica_constantes.dart';
import '../../domain/sugestao_venda_ranking.dart';
import 'relatorio_export_util.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioSugestoesVendaPage extends StatefulWidget {
  const RelatorioSugestoesVendaPage({
    super.key,
    required this.metricaRepository,
    required this.produtoRepository,
  });

  final SugestaoVendaMetricaRepository metricaRepository;
  final ProdutoRepository produtoRepository;

  @override
  State<RelatorioSugestoesVendaPage> createState() =>
      _RelatorioSugestoesVendaPageState();
}

class _RelatorioSugestoesVendaPageState extends State<RelatorioSugestoesVendaPage> {
  LimitesPeriodo? _limites;
  List<SugestaoVendaRankingLinha> _linhas = const [];

  final NumberFormat _pct = NumberFormat('#,##0.0', 'pt_BR');
  final NumberFormat _int = NumberFormat('#,##0', 'pt_BR');

  void _carregar() {
    final lim = _limites;
    if (lim == null) {
      setState(() => _linhas = const []);
      return;
    }
    final lista = widget.metricaRepository.listarRanking(
      inicio: lim.$1,
      fim: lim.$2,
    );
    setState(() => _linhas = lista);
  }

  String _nomeProduto(int id) =>
      widget.produtoRepository.obterPorId(id)?.nome ?? '#$id';

  String _rotuloFonte(String fonte) => switch (fonte) {
        SugestaoVendaMetricaFonte.historico => 'Historico',
        SugestaoVendaMetricaFonte.cadastro => 'Cadastro',
        _ => fonte,
      };

  int get _totalAceites =>
      _linhas.fold<int>(0, (s, l) => s + l.aceites);

  int get _totalExibicoes =>
      _linhas.fold<int>(0, (s, l) => s + l.oportunidades);

  List<List<String>> _linhasCsv() => [
        [
          'Produto origem',
          'Produto sugerido',
          'Fonte',
          'Exibicoes',
          'Aceites',
          'Ignorados',
          'Taxa aceite %',
        ],
        ..._linhas.map(
          (l) => [
            _nomeProduto(l.produtoOrigemId),
            _nomeProduto(l.produtoSugeridoId),
            _rotuloFonte(l.fonte),
            '${l.oportunidades}',
            '${l.aceites}',
            '${l.ignorados}',
            _pct.format(l.taxaAceite * 100),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestoes de venda — ranking'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'sugestoes_venda_ranking',
            paginasPdf: () {
              final rows = _linhasCsv();
              if (rows.length <= 1) return const ['(vazio)'];
              return relatorioMontarPaginasTabela(
                titulo: 'Sugestoes de venda — ranking',
                cabecalho: rows.first,
                linhas: rows.skip(1).toList(),
              );
            },
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: (lim) {
              _limites = lim;
              _carregar();
            },
            onAtualizar: _carregar,
            resumo: _linhas.isEmpty
                ? null
                : Text(
                    '${_int.format(_totalAceites)} aceite(s) · '
                    '${_int.format(_totalExibicoes)} oportunidade(s) no periodo',
                    style: theme.textTheme.bodySmall,
                  ),
          ),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(
                    child: Text(
                      'Sem metricas no periodo. Use o PDV para gerar dados.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _linhas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = _linhas[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${_nomeProduto(l.produtoOrigemId)} → '
                          '${_nomeProduto(l.produtoSugeridoId)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_rotuloFonte(l.fonte)} · '
                          '${l.aceites} aceite(s) · '
                          '${l.ignorados} ignorado(s) · '
                          '${l.oportunidades} exib.',
                        ),
                        trailing: Text(
                          '${_pct.format(l.taxaAceite * 100)}%',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

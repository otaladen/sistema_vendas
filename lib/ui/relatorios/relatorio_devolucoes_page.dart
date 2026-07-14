import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/venda_repository.dart';
import '../../domain/relatorios/devolucao_relatorio.dart';
import 'relatorio_export_util.dart';
import 'relatorio_helpers.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioDevolucoesPage extends StatefulWidget {
  const RelatorioDevolucoesPage({super.key, required this.vendaRepository});

  final VendaRepository vendaRepository;

  @override
  State<RelatorioDevolucoesPage> createState() =>
      _RelatorioDevolucoesPageState();
}

class _RelatorioDevolucoesPageState extends State<RelatorioDevolucoesPage> {
  final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');
  final DateFormat _fmtData = DateFormat('dd/MM/yyyy');

  LimitesPeriodo? _limites;
  bool _modoResumo = false;
  List<DevolucaoDetalheLinha> _detalhes = [];
  List<DevolucaoProdutoResumoLinha> _resumo = [];

  void _carregar(LimitesPeriodo limites) {
    final regs = widget.vendaRepository.listarRegistrosDevolucaoPorPeriodo(
      relatorioPeriodoFiltro(limites),
    );
    final detalhes = montarDetalhesDevolucao(widget.vendaRepository, regs);
    setState(() {
      _limites = limites;
      _detalhes = detalhes;
      _resumo = agregarDevolucoesPorProduto(detalhes);
    });
  }

  String _fmt(double v) => 'R\$ ${_moeda.format(v)}';

  List<List<String>> _linhasCsv() {
    if (_modoResumo) {
      return [
        ['Produto', 'Quantidade', 'Valor', 'Registros'],
        ..._resumo.map(
          (l) => [
            l.nome,
            '${l.quantidade}',
            _moeda.format(l.valor),
            '${l.registros}',
          ],
        ),
      ];
    }
    return [
      [
        'Data',
        'Tipo',
        'Nota',
        'Cliente',
        'Produto',
        'Qtd',
        'Valor',
        'Motivo',
        'Registrado por',
      ],
      ..._detalhes.map(
        (l) => [
          _fmtData.format(l.data),
          l.tipo,
          '${l.numeroVenda}',
          l.cliente,
          l.produto,
          '${l.quantidade}',
          _moeda.format(l.valor),
          l.motivo,
          l.registradoPor,
        ],
      ),
    ];
  }

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    if (_modoResumo) {
      return relatorioMontarPaginasTabela(
        titulo: 'DEVOLUCOES POR PRODUTO',
        subtitulo: formatarIntervaloPeriodo(_limites!),
        cabecalho: ['Produto', 'Qtd', 'Valor', 'Reg.'],
        linhas: _resumo
            .map(
              (l) => [
                l.nome,
                '${l.quantidade}',
                _moeda.format(l.valor),
                '${l.registros}',
              ],
            )
            .toList(),
      );
    }
    return relatorioMontarPaginasTabela(
      titulo: 'DEVOLUCOES E TROCAS',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['Data', 'Tipo', 'Nota', 'Cliente', 'Produto', 'Qtd', 'Valor'],
      linhas: _detalhes
          .take(400)
          .map(
            (l) => [
              _fmtData.format(l.data),
              l.tipo,
              '${l.numeroVenda}',
              l.cliente,
              l.produto,
              '${l.quantidade}',
              _moeda.format(l.valor),
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final totalValor = totalValorDevolucoes(_detalhes);
    final totalQtd = _detalhes
        .where((d) => d.tipo == 'Devolucao' || d.tipo.contains('entrada'))
        .fold<int>(0, (s, d) => s + d.quantidade);
    final vazio = _modoResumo ? _resumo.isEmpty : _detalhes.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devolucoes e trocas'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: _modoResumo
                ? 'devolucoes_por_produto'
                : 'devolucoes_detalhe',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: _carregar,
            onAtualizar: lim != null ? () => _carregar(lim) : null,
            filtrosExtras: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Detalhe')),
                  ButtonSegment(value: true, label: Text('Por produto')),
                ],
                emptySelectionAllowed: false,
                selected: {_modoResumo},
                onSelectionChanged: (s) => setState(() => _modoResumo = s.first),
              ),
            ],
            resumo: lim == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatarIntervaloPeriodo(lim),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_detalhes.length} linha(s) · '
                        '${_nfInt.format(totalQtd)} un. devolvidas · '
                        'Valor ref. ${_fmt(totalValor)}',
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: vazio
                ? const Center(
                    child: Text('Nenhuma devolucao ou troca no periodo.'),
                  )
                : _modoResumo
                    ? ListView.separated(
                        itemCount: _resumo.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final l = _resumo[i];
                          return ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text(l.nome),
                            subtitle: Text(
                              '${_nfInt.format(l.quantidade)} un. · '
                              '${_fmt(l.valor)} · ${l.registros} registro(s)',
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        itemCount: _detalhes.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final l = _detalhes[i];
                          return ListTile(
                            title: Text('${l.tipo} · Nota ${l.numeroVenda}'),
                            subtitle: Text(
                              '${_fmtData.format(l.data)} · ${l.cliente} · '
                              '${l.produto} · ${_nfInt.format(l.quantidade)} un. · '
                              '${_fmt(l.valor)}'
                              '${l.motivo.isNotEmpty ? " · ${l.motivo}" : ""}'
                              '${l.registradoPor.isNotEmpty ? " · ${l.registradoPor}" : ""}',
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

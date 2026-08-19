import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../domain/relatorio_performance_entregas.dart';
import '../../model/venda.dart';
import 'relatorio_export_util.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioPerformanceEntregasPage extends StatefulWidget {
  const RelatorioPerformanceEntregasPage({
    super.key,
    required this.vendaRepository,
  });

  final dynamic vendaRepository;

  @override
  State<RelatorioPerformanceEntregasPage> createState() =>
      _RelatorioPerformanceEntregasPageState();
}

class _RelatorioPerformanceEntregasPageState
    extends State<RelatorioPerformanceEntregasPage> {
  final NumberFormat _pct = NumberFormat('#,##0.0', 'pt_BR');
  LimitesPeriodo? _limites;
  String _dimensao = 'motorista';
  List<RelatorioPerformanceEntregaLinha> _linhas = [];
  List<Venda> _entregas = [];

  Future<void> _calcular(LimitesPeriodo limites) async {
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        await repo.hidratarEntregas(limit: 500);
      } catch (_) {}
    }
    if (!mounted) return;
    final lista = (repo.listarEntregas() as List).cast<Venda>();
    final agg = RelatorioPerformanceEntregas.agregar(
      entregas: lista,
      inicio: limites.$1,
      fim: limites.$2,
      dimensao: _dimensao,
    );
    setState(() {
      _limites = limites;
      _entregas = lista;
      _linhas = agg;
    });
  }

  void _recalcular() {
    final lim = _limites;
    if (lim == null) return;
    setState(() {
      _linhas = RelatorioPerformanceEntregas.agregar(
        entregas: _entregas,
        inicio: lim.$1,
        fim: lim.$2,
        dimensao: _dimensao,
      );
    });
  }

  int get _entregues => _linhas.fold<int>(0, (s, e) => s + e.entregues);
  int get _insucessos => _linhas.fold<int>(0, (s, e) => s + e.insucessos);
  int get _voltou => _linhas.fold<int>(0, (s, e) => s + e.cargaVoltou);

  List<List<String>> _linhasCsv() => [
        [
          _dimensao == 'veiculo' ? 'Veiculo' : 'Motorista',
          'Entregues',
          'Insucessos',
          'Taxa %',
          'Carga voltou',
          'Ausente',
          'Endereco',
          'Recusou',
        ],
        ..._linhas.map(
          (e) => [
            e.nome,
            '${e.entregues}',
            '${e.insucessos}',
            e.taxaSucessoPct.toStringAsFixed(1),
            '${e.cargaVoltou}',
            '${e.ausente}',
            '${e.enderecoErrado}',
            '${e.recusou}',
          ],
        ),
      ];

  List<String> _paginasPdf() {
    if (_limites == null) return [];
    return relatorioMontarPaginasTabela(
      titulo: _dimensao == 'veiculo'
          ? 'PERFORMANCE ENTREGAS — VEICULO'
          : 'PERFORMANCE ENTREGAS — MOTORISTA',
      subtitulo: formatarIntervaloPeriodo(_limites!),
      cabecalho: ['Nome', 'OK', 'Falha', 'Taxa', 'Voltou'],
      linhas: _linhas
          .map(
            (e) => [
              e.nome,
              '${e.entregues}',
              '${e.insucessos}',
              '${e.taxaSucessoPct.toStringAsFixed(0)}%',
              '${e.cargaVoltou}',
            ],
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lim = _limites;
    final tentativas = _entregues + _insucessos;
    final taxaGeral = tentativas == 0 ? 0.0 : _entregues / tentativas * 100;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance de entregas'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'performance_entregas',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          RelatorioPeriodoPainel(
            vendaRepository: widget.vendaRepository,
            onPeriodoChanged: (lim) => unawaited(_calcular(lim)),
            onAtualizar: lim != null ? () => unawaited(_calcular(lim)) : null,
            filtrosExtras: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'motorista',
                    label: Text('Motorista'),
                  ),
                  ButtonSegment(
                    value: 'veiculo',
                    label: Text('Veiculo'),
                  ),
                ],
                emptySelectionAllowed: false,
                selected: {_dimensao},
                onSelectionChanged: (s) {
                  setState(() => _dimensao = s.first);
                  _recalcular();
                },
              ),
            ],
            resumo: lim == null
                ? null
                : Text(
                    '${formatarIntervaloPeriodo(lim)} · '
                    '$_entregues entregue(s) · $_insucessos insucesso(s) · '
                    'taxa ${_pct.format(taxaGeral)}% · '
                    '$_voltou carga(s) voltou a loja.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(
                    child: Text('Nenhuma entrega no periodo.'),
                  )
                : ListView.builder(
                    itemCount: _linhas.length,
                    itemBuilder: (context, i) {
                      final a = _linhas[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(a.nome),
                        subtitle: Text(
                          '${a.entregues} entregue · ${a.insucessos} insucesso · '
                          'voltou ${a.cargaVoltou}'
                          '${a.ausente + a.enderecoErrado + a.recusou > 0 ? ' · '
                              'ausente ${a.ausente} / end. ${a.enderecoErrado} / '
                              'recusou ${a.recusou}' : ''}',
                        ),
                        trailing: Text(
                          '${a.taxaSucessoPct.toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.titleSmall,
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

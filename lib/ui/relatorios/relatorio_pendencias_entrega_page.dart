import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/relatorios/pendencia_entrega_relatorio.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../widgets/lan_api_feedback.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioPendenciasEntregaPage extends StatefulWidget {
  const RelatorioPendenciasEntregaPage({
    super.key,
    required this.vendaRepository,
    this.clienteRepository,
    this.vendedorRepository,
  });

  final dynamic vendaRepository;
  final dynamic clienteRepository;
  final dynamic vendedorRepository;

  @override
  State<RelatorioPendenciasEntregaPage> createState() =>
      _RelatorioPendenciasEntregaPageState();
}

class _RelatorioPendenciasEntregaPageState
    extends State<RelatorioPendenciasEntregaPage> {
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');
  final DateFormat _fmtData = DateFormat('dd/MM/yyyy');

  TipoPendenciaEntregaRelatorio _filtroTipo =
      TipoPendenciaEntregaRelatorio.todas;
  List<LinhaPendenciaEntregaRelatorio> _linhas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final repo = widget.vendaRepository;
    if (repo is VendaApiRepository) {
      try {
        await repo.hidratarEntregas(limit: 500);
      } on Exception catch (e) {
        if (mounted) {
          LanApiFeedback.snackAviso(context, e, prefixo: 'Pendencias');
        }
      }
    }
    if (!mounted) return;

    final vendas = _vendasPendentes(repo);
    setState(() {
      _linhas = montarLinhasPendenciaEntrega(
        vendas,
        filtroTipo: _filtroTipo,
        clienteRepository: widget.clienteRepository,
        vendedorRepository: widget.vendedorRepository,
        itensDaVenda: (v) {
          try {
            final via = repo.listarItensPorVenda(v.id);
            if (via is List && via.isNotEmpty) {
              return List<ItemVenda>.from(via);
            }
          } catch (_) {}
          return const <ItemVenda>[];
        },
      );
      _carregando = false;
    });
  }

  List<Venda> _vendasPendentes(dynamic repo) {
    if (repo is VendaApiRepository) {
      final mapa = <int, Venda>{};
      void addAll(Iterable<Venda> lista) {
        for (final v in lista) {
          if (v.cancelada || v.status != 'finalizada' || !v.entregaPendente) {
            continue;
          }
          mapa[v.id] = v;
        }
      }

      addAll(repo.listarEntregas());
      addAll(repo.listarTodas());
      return mapa.values.toList();
    }
    return (repo.listarListagemVendasCompleto(
      const FiltroListagemVendas(
        textoBusca: '',
        filtroCancelamento: 'ativas',
        canceladaPorFiltro: 'todos',
        formaPagamento: 'todos',
        tipoEntrega: 'todos',
        entregaPendente: 'sim',
      ),
    ) as List)
        .cast<Venda>();
  }

  List<List<String>> _linhasCsv() => [
        [
          'Nota',
          'Cliente',
          'Produto',
          'Codigo',
          'Qtd pendente',
          'Tipo',
          'Status entrega',
          'Data venda',
          'Data marcada',
          'Vendedor',
        ],
        ..._linhas.map(
          (l) => [
            '${l.numeroOrcamento}',
            l.cliente,
            l.produto,
            l.codigoProduto,
            '${l.quantidadePendente}',
            rotuloTipoPendenciaEntrega(l.tipo),
            relatorioRotuloStatusEntrega(l.statusEntrega),
            _fmtData.format(l.dataVenda),
            l.dataEntregaMarcada != null
                ? _fmtData.format(l.dataEntregaMarcada!)
                : '',
            l.vendedor,
          ],
        ),
      ];

  List<String> _paginasPdf() => relatorioMontarPaginasTabela(
        titulo: 'PENDENCIAS DE RETIRADA E ENTREGA',
        subtitulo: '${_linhas.length} linha(s)',
        cabecalho: [
          'Nota',
          'Cliente',
          'Produto',
          'Qtd',
          'Tipo',
          'Status',
        ],
        linhas: _linhas
            .take(500)
            .map(
              (l) => [
                '${l.numeroOrcamento}',
                l.cliente,
                l.produto,
                '${l.quantidadePendente}',
                rotuloTipoPendenciaEntrega(l.tipo),
                relatorioRotuloStatusEntrega(l.statusEntrega),
              ],
            )
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    final totalQtd =
        _linhas.fold<int>(0, (s, l) => s + l.quantidadePendente);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendencias de retirada e entrega'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'pendencias_entrega',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<TipoPendenciaEntregaRelatorio>(
                    segments: const [
                      ButtonSegment(
                        value: TipoPendenciaEntregaRelatorio.todas,
                        label: Text('Todas'),
                      ),
                      ButtonSegment(
                        value: TipoPendenciaEntregaRelatorio.retiradaFutura,
                        label: Text('Retirada'),
                      ),
                      ButtonSegment(
                        value: TipoPendenciaEntregaRelatorio.carreto,
                        label: Text('Carreto'),
                      ),
                    ],
                    selected: {_filtroTipo},
                    onSelectionChanged: (s) {
                      setState(() => _filtroTipo = s.first);
                      _carregar();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _carregando ? null : _carregar,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _carregando
                    ? 'Carregando…'
                    : '${_linhas.length} linha(s) · '
                        '${_nfInt.format(totalQtd)} un. pendente(s)',
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _linhas.isEmpty
                    ? const Center(
                        child: Text('Nenhuma pendencia de entrega.'),
                      )
                    : ListView.separated(
                        itemCount: _linhas.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final l = _linhas[i];
                          return ListTile(
                            title: Text(
                              'Ped. ${l.numeroOrcamento} · ${l.cliente}',
                            ),
                            subtitle: Text(
                              '${l.produto} · '
                              '${rotuloTipoPendenciaEntrega(l.tipo)} · '
                              '${_nfInt.format(l.quantidadePendente)} un.\n'
                              '${_fmtData.format(l.dataVenda)}'
                              '${l.vendedor.isEmpty ? '' : ' · ${l.vendedor}'}',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

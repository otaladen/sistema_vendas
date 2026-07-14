import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/venda_repository.dart';
import '../../domain/entrega_venda_helper.dart';
import '../../domain/relatorios/pendencia_entrega_relatorio.dart';
import 'relatorio_entregas_helper.dart';
import 'relatorio_export_util.dart';
import 'widgets/relatorio_exportacoes_menu.dart';

class RelatorioPendenciasEntregaPage extends StatefulWidget {
  const RelatorioPendenciasEntregaPage({super.key, required this.vendaRepository});

  final VendaRepository vendaRepository;

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

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    final vendas = widget.vendaRepository.listarListagemVendasCompleto(
      const FiltroListagemVendas(
        textoBusca: '',
        filtroCancelamento: 'ativas',
        canceladaPorFiltro: 'todos',
        formaPagamento: 'todos',
        tipoEntrega: 'todos',
        entregaPendente: 'sim',
      ),
    );
    setState(
      () => _linhas = montarLinhasPendenciaEntrega(
        vendas,
        filtroTipo: _filtroTipo,
      ),
    );
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
        subtitulo:
            '${_linhas.length} linha(s) · ${totalUnidadesPendencia(_linhas)} un.',
        cabecalho: ['Nota', 'Cliente', 'Produto', 'Qtd', 'Tipo', 'Status'],
        linhas: _linhas
            .take(400)
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

  String _rotuloFiltro(TipoPendenciaEntregaRelatorio t) {
    switch (t) {
      case TipoPendenciaEntregaRelatorio.todas:
        return 'Todas';
      case TipoPendenciaEntregaRelatorio.retiradaFutura:
        return 'Retirada futura';
      case TipoPendenciaEntregaRelatorio.carreto:
        return 'Carreto';
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalUn = totalUnidadesPendencia(_linhas);
    final retirada = _linhas
        .where((l) => l.tipo == EntregaVendaHelper.tipoRetiradaFutura)
        .length;
    final carreto = _linhas
        .where((l) => l.tipo == EntregaVendaHelper.tipoEntregaLoja)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendencias de retirada e entrega'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'pendencias_entrega',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregar,
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<TipoPendenciaEntregaRelatorio>(
                    key: ValueKey(_filtroTipo),
                    initialValue: _filtroTipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de pendencia',
                      isDense: true,
                    ),
                    items: TipoPendenciaEntregaRelatorio.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(_rotuloFiltro(t)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _filtroTipo = v);
                      _carregar();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_linhas.length} linha(s) · '
                    '${_nfInt.format(totalUn)} un. pendentes · '
                    'Retirada futura: $retirada · Carreto: $carreto',
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(
                    child: Text('Nenhuma pendencia de retirada ou entrega.'),
                  )
                : ListView.separated(
                    itemCount: _linhas.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = _linhas[i];
                      final dm = l.dataEntregaMarcada;
                      return ListTile(
                        title: Text(
                          'Nota ${l.numeroOrcamento} · ${l.cliente}',
                        ),
                        subtitle: Text(
                          '${l.codigoProduto.isNotEmpty ? "${l.codigoProduto} — " : ""}'
                          '${l.produto} · '
                          '${_nfInt.format(l.quantidadePendente)} un. · '
                          '${rotuloTipoPendenciaEntrega(l.tipo)} · '
                          '${relatorioRotuloStatusEntrega(l.statusEntrega)} · '
                          'Venda ${_fmtData.format(l.dataVenda)}'
                          '${dm != null ? " · Marcada ${_fmtData.format(dm)}" : ""}'
                          '${l.vendedor.isNotEmpty ? " · ${l.vendedor}" : ""}',
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

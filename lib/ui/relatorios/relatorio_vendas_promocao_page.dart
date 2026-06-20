import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/promocao_repository.dart';
import '../../data/venda_repository.dart';
import 'relatorio_cores.dart';
import 'relatorio_periodo.dart';
import 'widgets/relatorio_exportacoes_menu.dart';
import 'widgets/relatorio_periodo_painel.dart';

class RelatorioVendasPromocaoPage extends StatefulWidget {
  const RelatorioVendasPromocaoPage({
    super.key,
    required this.vendaRepository,
    required this.promocaoRepository,
  });

  final VendaRepository vendaRepository;
  final PromocaoRepository promocaoRepository;

  @override
  State<RelatorioVendasPromocaoPage> createState() =>
      _RelatorioVendasPromocaoPageState();
}

class _RelatorioVendasPromocaoPageState extends State<RelatorioVendasPromocaoPage> {
  LimitesPeriodo? _limites;
  int? _filtroPromocaoId;
  List<VendaPromocaoRelatorioLinha> _linhas = [];

  final NumberFormat _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  final NumberFormat _nfInt = NumberFormat('#,##0', 'pt_BR');

  void _carregar() {
    final lim = _limites;
    if (lim == null) {
      setState(() => _linhas = []);
      return;
    }
    final lista = widget.vendaRepository.listarVendasPromocaoPeriodo(
      inicio: lim.$1,
      fim: lim.$2,
      promocaoId: _filtroPromocaoId,
    );
    setState(() => _linhas = lista);
  }

  String _fmtMoeda(double v) => 'R\$ ${_nfMoeda.format(v)}';

  Map<String, ({int qtd, double total, double lucro})> _resumoPorPromocao() {
    final map = <String, ({int qtd, double total, double lucro})>{};
    for (final l in _linhas) {
      final k = l.promocaoNome;
      final atual = map[k];
      map[k] = (
        qtd: (atual?.qtd ?? 0) + l.quantidade,
        total: (atual?.total ?? 0) + l.total,
        lucro: (atual?.lucro ?? 0) + l.lucro,
      );
    }
    return map;
  }

  List<List<String>> _linhasCsv() => [
        [
          'Data',
          'Nota',
          'Campanha',
          'Codigo',
          'Produto',
          'Qtd',
          'Unit',
          'Total',
          'Lucro',
          'Cliente',
        ],
        ..._linhas.map(
          (l) => [
            DateFormat('dd/MM/yyyy').format(l.dataVenda),
            '${l.nota}',
            l.promocaoNome,
            l.codigoInterno,
            l.produtoNome,
            '${l.quantidade}',
            _nfMoeda.format(l.valorUnitario),
            _nfMoeda.format(l.total),
            _nfMoeda.format(l.lucro),
            l.clienteNome,
          ],
        ),
      ];

  List<String> _paginasPdf() {
    final resumo = _resumoPorPromocao().entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final buf = StringBuffer();
    buf.writeln('VENDAS EM PROMOCAO');
    buf.writeln('${_linhas.length} linha(s)');
    buf.writeln('');
    buf.writeln('RESUMO POR CAMPANHA');
    for (final e in resumo) {
      buf.writeln(
        '${e.key}: ${_nfInt.format(e.value.qtd)} un · '
        '${_fmtMoeda(e.value.total)} · lucro ${_fmtMoeda(e.value.lucro)}',
      );
    }
    buf.writeln('');
    buf.writeln('DETALHE');
    for (final l in _linhas.take(200)) {
      buf.writeln(
        '${DateFormat('dd/MM/yy').format(l.dataVenda)} '
        '${l.promocaoNome} · ${l.codigoInterno} · '
        '${l.quantidade} x ${_nfMoeda.format(l.valorUnitario)}',
      );
    }
    return [buf.toString()];
  }

  @override
  Widget build(BuildContext context) {
    final tQtd = _linhas.fold<int>(0, (s, e) => s + e.quantidade);
    final tVal = _linhas.fold<double>(0, (s, e) => s + e.total);
    final tLuc = _linhas.fold<double>(0, (s, e) => s + e.lucro);
    final promos = widget.promocaoRepository.listarPorNome();
    final resumo = _resumoPorPromocao();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas em promocao'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'vendas_promocao',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RelatorioPeriodoPainel(
            onPeriodoChanged: (lim) {
              setState(() => _limites = lim);
              _carregar();
            },
            onAtualizar: _carregar,
            filtrosExtras: [
              DropdownButtonFormField<int?>(
                key: ValueKey(_filtroPromocaoId),
                initialValue: _filtroPromocaoId,
                decoration: const InputDecoration(
                  labelText: 'Campanha',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todas as campanhas'),
                  ),
                  ...promos.map(
                    (p) => DropdownMenuItem<int?>(
                      value: p.id,
                      child: Text(p.nome, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() => _filtroPromocaoId = v);
                  _carregar();
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${_linhas.length} linha(s) · ${_nfInt.format(tQtd)} un · '
              '${_fmtMoeda(tVal)} · lucro ${_fmtMoeda(tLuc)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (resumo.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: resumo.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: Icon(
                        Icons.local_offer,
                        size: 18,
                        color: corRelVendasPromocao(context),
                      ),
                      label: Text(
                        '${e.key}: ${_nfInt.format(e.value.qtd)} un · '
                        '${_fmtMoeda(e.value.total)}',
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Text(
                      _limites == null
                          ? 'Escolha o periodo.'
                          : 'Nenhuma venda com promocao neste periodo.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _linhas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final l = _linhas[i];
                      return Card(
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.local_offer_outlined,
                            color: corRelVendasPromocao(context),
                          ),
                          title: Text(
                            l.produtoNome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy').format(l.dataVenda)} · '
                            '${l.promocaoNome} · ${l.clienteNome}',
                          ),
                          trailing: Text(
                            '${_fmtMoeda(l.total)}\n'
                            'Lucro ${_fmtMoeda(l.lucro)}',
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodySmall,
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

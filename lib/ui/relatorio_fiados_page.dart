import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/cliente_repository.dart';
import '../data/titulo_receber_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/cliente.dart';
import 'relatorios/relatorio_drill_down.dart';
import 'relatorios/relatorio_export_util.dart';
import 'relatorios/widgets/relatorio_exportacoes_menu.dart';

class _GrupoFiadoCliente {
  _GrupoFiadoCliente({
    required this.clienteId,
    required this.nome,
    required this.cliente,
    required this.titulos,
  });

  final int clienteId;
  final String nome;
  final Cliente? cliente;
  final List<TituloReceberResumoLinha> titulos;

  double get saldoTotal =>
      titulos.fold<double>(0, (s, l) => s + l.titulo.saldo);

  int get maxDiasAtraso => titulos.fold<int>(
        0,
        (m, l) => l.diasAtraso > m ? l.diasAtraso : m,
      );

  bool get temVencido => titulos.any((l) => l.diasAtraso > 0);
}

/// Relatório de títulos de fiado em aberto.
class RelatorioFiadosPage extends StatefulWidget {
  const RelatorioFiadosPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    this.vendedorRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository? vendedorRepository;

  @override
  State<RelatorioFiadosPage> createState() => _RelatorioFiadosPageState();
}

class _RelatorioFiadosPageState extends State<RelatorioFiadosPage> {
  static final _fmtData = DateFormat('dd/MM/yyyy');
  static final _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool _somenteVencidos = false;
  bool _agruparPorCliente = true;
  List<TituloReceberResumoLinha> _linhas = [];
  List<_GrupoFiadoCliente> _grupos = [];

  @override
  void initState() {
    super.initState();
    _atualizar();
  }

  void _atualizar() {
    widget.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final linhas = widget.vendaRepository.titulos.listarTodosAbertos(
      somenteVencidos: _somenteVencidos,
    );
    final map = <int, _GrupoFiadoCliente>{};
    for (final l in linhas) {
      final cid = l.titulo.cliente.targetId;
      final cli = l.titulo.cliente.target ??
          (cid > 0 ? widget.clienteRepository.obterPorId(cid) : null);
      final nome = l.nomeCliente.trim().isNotEmpty
          ? l.nomeCliente
          : (cli?.nomeRazao ?? 'Cliente #$cid');
      map.putIfAbsent(
        cid,
        () => _GrupoFiadoCliente(
          clienteId: cid,
          nome: nome,
          cliente: cli,
          titulos: [],
        ),
      );
      map[cid]!.titulos.add(l);
    }
    final grupos = map.values.toList()
      ..sort((a, b) => b.saldoTotal.compareTo(a.saldoTotal));
    setState(() {
      _linhas = linhas;
      _grupos = grupos;
    });
  }

  List<List<String>> _linhasCsv() {
    final cab = [
      'Cliente',
      'Venda',
      'Parcela',
      'Vencimento',
      'Dias atraso',
      'Saldo',
      'Bloqueado fiado',
      'Limite credito',
    ];
    final rows = <List<String>>[cab];
    for (final l in _linhas) {
      final cid = l.titulo.cliente.targetId;
      final cli = cid > 0 ? widget.clienteRepository.obterPorId(cid) : null;
      rows.add([
        l.nomeCliente,
        '${l.numeroOrcamento}',
        '${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
        _fmtData.format(l.titulo.vencimento.toLocal()),
        '${l.diasAtraso}',
        _fmtMoeda.format(l.titulo.saldo),
        cli?.bloqueadoFiado == true ? 'sim' : 'nao',
        cli != null ? _fmtMoeda.format(cli.limiteCredito) : '',
      ]);
    }
    return rows;
  }

  List<String> _paginasPdf() {
    final total = _linhas.fold<double>(0, (s, l) => s + l.titulo.saldo);
    final linhasTab = _linhas
        .map(
          (l) => [
            l.nomeCliente,
            '${l.numeroOrcamento}',
            '${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
            _fmtData.format(l.titulo.vencimento.toLocal()),
            '${l.diasAtraso}',
            _fmtMoeda.format(l.titulo.saldo),
          ],
        )
        .toList();
    return relatorioMontarPaginasTabela(
      titulo: 'FIADOS EM ABERTO',
      subtitulo:
          '${_linhas.length} titulo(s) · Total ${_fmtMoeda.format(total)}'
          '${_somenteVencidos ? ' · Somente vencidos' : ''}',
      cabecalho: [
        'Cliente',
        'Venda',
        'Parc',
        'Vencimento',
        'Atraso',
        'Saldo',
      ],
      linhas: linhasTab,
    );
  }

  Widget? _chipAlertaCliente(Cliente? cli, double saldoGrupo) {
    if (cli == null) return null;
    final chips = <Widget>[];
    if (cli.bloqueadoFiado) {
      chips.add(
        Chip(
          label: const Text('Fiado bloqueado'),
          visualDensity: VisualDensity.compact,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    }
    if (cli.limiteCredito > 0 && saldoGrupo > cli.limiteCredito + 0.01) {
      chips.add(
        Chip(
          label: const Text('Acima do limite'),
          visualDensity: VisualDensity.compact,
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
        ),
      );
    }
    if (chips.isEmpty) return null;
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  @override
  Widget build(BuildContext context) {
    final totalSaldo = _linhas.fold<double>(
      0,
      (s, l) => s + l.titulo.saldo,
    );
    final qtdVencidos = _linhas.where((l) => l.diasAtraso > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiados em aberto'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'fiados_abertos',
            paginasPdf: _paginasPdf,
            linhasCsv: _linhasCsv,
          ),
          IconButton(
            onPressed: _atualizar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_linhas.length} titulo(s) · ${_grupos.length} cliente(s) · '
                  'Total: ${_fmtMoeda.format(totalSaldo)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (qtdVencidos > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$qtdVencidos titulo(s) vencido(s)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label: const Text('Só vencidos'),
                      selected: _somenteVencidos,
                      onSelected: (v) {
                        setState(() => _somenteVencidos = v);
                        _atualizar();
                      },
                    ),
                    FilterChip(
                      label: const Text('Agrupar por cliente'),
                      selected: _agruparPorCliente,
                      onSelected: (v) => setState(() => _agruparPorCliente = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _linhas.isEmpty
                ? const Center(child: Text('Nenhum título em aberto.'))
                : _agruparPorCliente
                    ? ListView.builder(
                        itemCount: _grupos.length,
                        itemBuilder: (context, i) {
                          final g = _grupos[i];
                          final alerta = _chipAlertaCliente(g.cliente, g.saldoTotal);
                          return ExpansionTile(
                            initiallyExpanded: g.temVencido,
                            leading: CircleAvatar(
                              backgroundColor: g.temVencido
                                  ? Theme.of(context)
                                      .colorScheme
                                      .errorContainer
                                  : null,
                              child: Text('${i + 1}'),
                            ),
                            title: Text(g.nome),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${g.titulos.length} titulo(s) · '
                                  '${_fmtMoeda.format(g.saldoTotal)}'
                                  '${g.maxDiasAtraso > 0 ? ' · ${g.maxDiasAtraso}d atraso max' : ''}',
                                ),
                                if (alerta != null) ...[
                                  const SizedBox(height: 4),
                                  alerta,
                                ],
                              ],
                            ),
                            trailing: g.clienteId > 0
                                ? IconButton(
                                    tooltip: 'Abrir cliente',
                                    icon: const Icon(Icons.person_outlined),
                                    onPressed: () => abrirClienteRelatorio(
                                      context,
                                      clienteRepository:
                                          widget.clienteRepository,
                                      vendaRepository: widget.vendaRepository,
                                      clienteId: g.clienteId,
                                      vendedorRepository:
                                          widget.vendedorRepository,
                                    ),
                                  )
                                : null,
                            children: g.titulos.map((l) {
                              final t = l.titulo;
                              final vid = t.venda.targetId;
                              return ListTile(
                                dense: true,
                                title: Text(
                                  'Venda ${l.numeroOrcamento} · '
                                  'Parc. ${t.numeroParcela}/${t.totalParcelas}',
                                ),
                                subtitle: Text(
                                  'Venc. ${_fmtData.format(t.vencimento.toLocal())}'
                                  '${l.diasAtraso > 0 ? ' · ${l.diasAtraso}d atraso' : ''}',
                                ),
                                trailing: Text(
                                  _fmtMoeda.format(t.saldo),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: l.diasAtraso > 0
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                ),
                                onTap: vid > 0
                                    ? () => mostrarDetalheVendaRelatorio(
                                          context,
                                          vendaRepository:
                                              widget.vendaRepository,
                                          vendaId: vid,
                                        )
                                    : null,
                              );
                            }).toList(),
                          );
                        },
                      )
                    : ListView.builder(
                        itemCount: _linhas.length,
                        itemBuilder: (context, i) {
                          final l = _linhas[i];
                          final t = l.titulo;
                          final cid = t.cliente.targetId;
                          final vid = t.venda.targetId;
                          return ListTile(
                            title: Text(l.nomeCliente),
                            subtitle: Text(
                              'Venda ${l.numeroOrcamento} · '
                              'Parc. ${t.numeroParcela}/${t.totalParcelas} · '
                              'Venc. ${_fmtData.format(t.vencimento.toLocal())}'
                              '${l.diasAtraso > 0 ? ' · ${l.diasAtraso}d atraso' : ''}',
                            ),
                            trailing: Text(
                              _fmtMoeda.format(t.saldo),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: l.diasAtraso > 0
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            onTap: () {
                              if (vid > 0) {
                                mostrarDetalheVendaRelatorio(
                                  context,
                                  vendaRepository: widget.vendaRepository,
                                  vendaId: vid,
                                );
                              } else if (cid > 0) {
                                mostrarResumoClienteRelatorio(
                                  context,
                                  clienteRepository: widget.clienteRepository,
                                  vendaRepository: widget.vendaRepository,
                                  clienteId: cid,
                                  vendedorRepository: widget.vendedorRepository,
                                );
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

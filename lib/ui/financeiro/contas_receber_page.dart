import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/titulo_receber_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/dashboard_alertas.dart';
import '../../domain/filtro_contas_receber.dart';
import '../../model/cliente.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_semantic_helper.dart';
import '../relatorios/relatorio_export_util.dart';
import '../relatorios/widgets/relatorio_exportacoes_menu.dart';
import '../widgets/receber_fiado_panel.dart';
import 'widgets/grafico_vencimentos.dart';

final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final DateFormat _dataFmt = DateFormat('dd/MM/yyyy');

/// Listagem de titulos a receber (fiado) com KPIs, filtros e recebimento.
class ContasReceberPage extends StatefulWidget {
  const ContasReceberPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
    required this.usuarioLogado,
    this.podeRegistrarRecebimento = false,
    this.filtroInicial = FiltroContasReceber.todos,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;
  final UsuarioSistema usuarioLogado;
  final bool podeRegistrarRecebimento;
  final FiltroContasReceber filtroInicial;

  @override
  State<ContasReceberPage> createState() => _ContasReceberPageState();
}

class _ContasReceberPageState extends State<ContasReceberPage> {
  late FiltroContasReceber _filtro;
  List<TituloReceberResumoLinha> _linhas = [];
  List<TituloReceberResumoLinha> _todas = [];

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial;
    _recarregar();
  }

  void _recarregar() {
    widget.vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final todas = widget.vendaRepository.titulos.listarTodosAbertos();
    final filtradas =
        todas.where((l) => ContasReceberHelper.atendeFiltro(l, _filtro)).toList();
    if (!mounted) return;
    setState(() {
      _todas = todas;
      _linhas = filtradas;
    });
  }

  double _soma(Iterable<TituloReceberResumoLinha> lista) =>
      lista.fold<double>(0, (s, l) => s + l.titulo.saldo);

  double get _kpiTotal => _soma(_todas);

  double get _kpiVencido =>
      _soma(_todas.where(ContasReceberHelper.ehVencido));

  double get _kpiVenceHoje =>
      _soma(_todas.where(ContasReceberHelper.ehVenceHoje));

  double get _kpiProximos7 =>
      _soma(_todas.where(ContasReceberHelper.ehProximos7));

  List<List<String>> _linhasCsvExport() {
    final cab = [
      'Cliente',
      'Venda',
      'Parcela',
      'Vencimento',
      'Dias atraso',
      'Saldo',
    ];
    final rows = <List<String>>[cab];
    for (final l in _linhas) {
      rows.add([
        l.nomeCliente,
        '${l.numeroOrcamento}',
        '${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
        _dataFmt.format(l.titulo.vencimento.toLocal()),
        '${l.diasAtraso}',
        _moeda.format(l.titulo.saldo),
      ]);
    }
    return rows;
  }

  List<String> _paginasPdfExport() {
    final total = _soma(_linhas);
    return relatorioMontarPaginasTabela(
      titulo: 'CONTAS A RECEBER (FIADO)',
      subtitulo:
          '${_linhas.length} titulo(s) · Total ${_moeda.format(total)} · ${_filtro.rotulo}',
      cabecalho: [
        'Cliente',
        'Venda',
        'Parc',
        'Vencimento',
        'Atraso',
        'Saldo',
      ],
      linhas: _linhas
          .map(
            (l) => [
              l.nomeCliente,
              '${l.numeroOrcamento}',
              '${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
              _dataFmt.format(l.titulo.vencimento.toLocal()),
              '${l.diasAtraso}',
              _moeda.format(l.titulo.saldo),
            ],
          )
          .toList(),
    );
  }

  Future<void> _abrirRecebimento({Cliente? cliente}) async {
    if (!widget.podeRegistrarRecebimento) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recebimento de fiado e feito no Caixa (permissao).'),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Receber fiado',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReceberFiadoPanel(
                    vendaRepository: widget.vendaRepository,
                    clienteRepository: widget.clienteRepository,
                    clienteInicial: cliente,
                    onRecebimentoRegistrado: (_) {
                      Navigator.pop(ctx);
                      _recarregar();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _recarregar();
  }

  Widget _kpiTile({
    required String titulo,
    required String valor,
    required Color bg,
    required Color border,
    required Color fg,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: fg.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: fg,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
    );
  }

  Cliente? _clienteDaLinha(TituloReceberResumoLinha l) {
    final cid = l.titulo.cliente.targetId;
    if (cid <= 0) return l.titulo.cliente.target;
    return l.titulo.cliente.target ??
        widget.clienteRepository.obterPorId(cid);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final infoBg = semantic.infoBg;
    final infoBorder = semantic.infoBorder;
    final infoFg = semantic.infoFg;
    final errBg = semantic.errorBg;
    final errBorder = semantic.errorBorder;
    final errFg = semantic.errorFg;
    final warnBg = semantic.warningBg;
    final warnBorder = semantic.warningBorder;
    final warnFg = semantic.warningFg;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas a receber'),
        actions: [
          RelatorioExportacoesMenu(
            nomeArquivo: 'contas_a_receber',
            paginasPdf: _paginasPdfExport,
            linhasCsv: _linhasCsvExport,
            mensagemSeVazio: 'Nenhum titulo para exportar.',
          ),
          if (widget.podeRegistrarRecebimento)
            IconButton(
              tooltip: 'Registrar recebimento',
              onPressed: _abrirRecebimento,
              icon: const Icon(Icons.payments_outlined),
            ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      floatingActionButton: widget.podeRegistrarRecebimento
          ? FloatingActionButton.extended(
              onPressed: _abrirRecebimento,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Receber'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                final estreito = c.maxWidth < 720;
                final kpis = [
                  _kpiTile(
                    titulo: 'Total a receber',
                    valor: _moeda.format(_kpiTotal),
                    bg: infoBg,
                    border: infoBorder,
                    fg: infoFg,
                    onTap: () {
                      setState(() => _filtro = FiltroContasReceber.todos);
                      _recarregar();
                    },
                  ),
                  _kpiTile(
                    titulo: 'Vencido',
                    valor: _moeda.format(_kpiVencido),
                    bg: errBg,
                    border: errBorder,
                    fg: errFg,
                    onTap: () {
                      setState(() => _filtro = FiltroContasReceber.vencidos);
                      _recarregar();
                    },
                  ),
                  _kpiTile(
                    titulo: 'Vence hoje',
                    valor: _moeda.format(_kpiVenceHoje),
                    bg: warnBg,
                    border: warnBorder,
                    fg: warnFg,
                    onTap: () {
                      setState(() => _filtro = FiltroContasReceber.venceHoje);
                      _recarregar();
                    },
                  ),
                  _kpiTile(
                    titulo: 'Proximos 7 dias',
                    valor: _moeda.format(_kpiProximos7),
                    bg: infoBg,
                    border: infoBorder,
                    fg: infoFg,
                    onTap: () {
                      setState(() => _filtro = FiltroContasReceber.proximos7);
                      _recarregar();
                    },
                  ),
                ];
                if (estreito) {
                  return Column(
                    children: [
                      for (var i = 0; i < kpis.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        kpis[i],
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var i = 0; i < kpis.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i > 0 ? 4 : 0,
                            right: i < kpis.length - 1 ? 4 : 0,
                          ),
                          child: kpis[i],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: GraficoVencimentosContasPagar(
              buckets: computeTitulosReceberVencimentosBuckets(_todas),
              titulo: 'Recebimentos previstos (fiado em aberto)',
              subtituloVazio:
                  'Nenhum fiado nas faixas de vencimento exibidas.',
              altura: 220,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: FiltroContasReceber.values.map((f) {
                final sel = _filtro == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.rotulo),
                    selected: sel,
                    onSelected: (_) {
                      setState(() => _filtro = f);
                      _recarregar();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${_linhas.length} titulo(s) · ${_moeda.format(_soma(_linhas))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: _linhas.isEmpty
                ? Center(
                    child: Text(
                      _filtro == FiltroContasReceber.todos
                          ? 'Nenhum titulo em aberto.'
                          : 'Nenhum titulo neste filtro.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: _linhas.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final l = _linhas[i];
                      final vencido = ContasReceberHelper.ehVencido(l);
                      final venceHoje = ContasReceberHelper.ehVenceHoje(l);
                      final cliente = _clienteDaLinha(l);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: vencido
                                    ? errBg
                                    : venceHoje
                                        ? warnBg
                                        : infoBg,
                                child: Icon(
                                  vencido
                                      ? Icons.warning_amber_rounded
                                      : Icons.receipt_long_outlined,
                                  color: vencido
                                      ? errFg
                                      : venceHoje
                                          ? warnFg
                                          : infoFg,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.nomeCliente,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Venda ${l.numeroOrcamento > 0 ? l.numeroOrcamento : l.titulo.venda.targetId} · '
                                      'Parc. ${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Text(
                                      'Venc.: ${_dataFmt.format(l.titulo.vencimento.toLocal())}'
                                      '${l.diasAtraso > 0 ? ' · ${l.diasAtraso} dia(s) atraso' : ''}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _moeda.format(l.titulo.saldo),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (widget.podeRegistrarRecebimento &&
                                      cliente != null)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () =>
                                          _abrirRecebimento(cliente: cliente),
                                      child: const Text('Receber'),
                                    ),
                                ],
                              ),
                            ],
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

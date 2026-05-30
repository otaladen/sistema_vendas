import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/models/conta_pagar.dart';
import '../../data/objectbox.dart';
import '../../data/sync/sync_write_trigger.dart';
import '../../main.dart';
import '../../objectbox.g.dart';
import 'widgets/grafico_vencimentos.dart';

final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final DateFormat _dataFmt = DateFormat('dd/MM/yyyy');

enum _FiltroStatusConta { todos, pendentes, pagos, atrasados }

/// Listagem de contas a pagar com KPIs, filtros por status e baixa rápida.
class ContasPagarPage extends StatefulWidget {
  const ContasPagarPage({
    super.key,
    required this.objectBox,
    this.saldoCaixaReferencia,
  });

  final ObjectBox objectBox;

  /// Saldo em caixa para linha de referência no gráfico (opcional).
  final double? saldoCaixaReferencia;

  @override
  State<ContasPagarPage> createState() => _ContasPagarPageState();
}

class _ContasPagarPageState extends State<ContasPagarPage> {
  _FiltroStatusConta _filtro = _FiltroStatusConta.todos;
  List<ContaPagar> _linhas = [];
  ContasPagarVencimentosBuckets _buckets = ContasPagarVencimentosBuckets.zero;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  DateTime _somenteData(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Atualiza [ContaPagarStatus.atrasado] para pendentes já vencidos (data local).
  void _sincronizarPendenteParaAtrasado() {
    final hoje = _somenteData(DateTime.now());
    for (final c in widget.objectBox.contaPagarBox.getAll()) {
      if (c.status != ContaPagarStatus.pendente) continue;
      if (_somenteData(c.dataVencimento).isBefore(hoje)) {
        c.status = ContaPagarStatus.atrasado;
        final id = widget.objectBox.contaPagarBox.put(c);
        notificarAlteracaoParaRede(entidade: 'conta_pagar', entidadeId: id);
      }
    }
  }

  void _recarregar() {
    _sincronizarPendenteParaAtrasado();
    final buckets = computeContasPagarVencimentosBuckets(
      widget.objectBox.contaPagarBox,
    );

    final box = widget.objectBox.contaPagarBox;
    final Query<ContaPagar> q;
    switch (_filtro) {
      case _FiltroStatusConta.todos:
        q = box.query().order(ContaPagar_.dataVencimento).build();
        break;
      case _FiltroStatusConta.pendentes:
        q = box
            .query(ContaPagar_.status.equals(ContaPagarStatus.pendente))
            .order(ContaPagar_.dataVencimento)
            .build();
        break;
      case _FiltroStatusConta.pagos:
        q = box
            .query(ContaPagar_.status.equals(ContaPagarStatus.pago))
            .order(ContaPagar_.dataVencimento, flags: Order.descending)
            .build();
        break;
      case _FiltroStatusConta.atrasados:
        q = box
            .query(ContaPagar_.status.equals(ContaPagarStatus.atrasado))
            .order(ContaPagar_.dataVencimento)
            .build();
        break;
    }
    try {
      final lista = q.find();
      if (!mounted) return;
      setState(() {
        _linhas = lista;
        _buckets = buckets;
      });
    } finally {
      q.close();
    }
  }

  double _somaPorStatus(String status) {
    var t = 0.0;
    for (final c in widget.objectBox.contaPagarBox.getAll()) {
      if (c.status == status) {
        t += c.valorParcela;
      }
    }
    return t;
  }

  double get _kpiPendente => _somaPorStatus(ContaPagarStatus.pendente);
  double get _kpiPago {
    var t = 0.0;
    for (final c in widget.objectBox.contaPagarBox.getAll()) {
      if (c.status == ContaPagarStatus.pago) {
        t += c.valorPago ?? c.valorParcela;
      }
    }
    return t;
  }

  double get _kpiAtrasado => _somaPorStatus(ContaPagarStatus.atrasado);

  String _nomeFornecedor(ContaPagar c) {
    final f = c.fornecedor.target;
    if (f == null) return '—';
    final nome = f.nomeFantasia.trim().isNotEmpty ? f.nomeFantasia : f.razaoSocial;
    return nome.trim().isEmpty ? '—' : nome;
  }

  Future<void> _confirmarBaixa(ContaPagar conta) async {
    if (conta.status == ContaPagarStatus.pago) return;

    final valorCtrl = TextEditingController(
      text: conta.valorParcela.toStringAsFixed(2).replaceAll('.', ','),
    );
    DateTime dataPg = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Dar baixa no pagamento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fornecedor: ${_nomeFornecedor(conta)}\n'
                      'Parcela: ${conta.numeroParcela}\n'
                      'Vencimento: ${_dataFmt.format(conta.dataVencimento)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: valorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valor pago',
                        prefixText: r'R$ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Data do pagamento'),
                      subtitle: Text(_dataFmt.format(dataPg)),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_today_outlined),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dataPg,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => dataPg = picked);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirmar pagamento'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) {
      valorCtrl.dispose();
      return;
    }

    final textoValor = valorCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final vp = double.tryParse(textoValor);
    valorCtrl.dispose();
    if (vp == null || vp <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor pago válido.')),
      );
      return;
    }

    conta.status = ContaPagarStatus.pago;
    conta.dataPagamento = dataPg;
    conta.valorPago = vp;
    final id = widget.objectBox.contaPagarBox.put(conta);
    notificarAlteracaoParaRede(entidade: 'conta_pagar', entidadeId: id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pagamento registrado.')),
    );
    _recarregar();
  }

  Widget _kpiTile({
    required String titulo,
    required String valor,
    required Color bg,
    required Color border,
    required Color fg,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelTopoKpisEGrafico(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final infoBg = semantic?.infoBg ?? const Color(0xFFEAF2FF);
    final infoBorder = semantic?.infoBorder ?? const Color(0xFF9EC0FF);
    final infoFg = semantic?.infoFg ?? const Color(0xFF1E3A8A);
    final okBg = semantic?.successBg ?? const Color(0xFFEAF8EF);
    final okBorder = semantic?.successBorder ?? const Color(0xFF8FD1A8);
    final okFg = semantic?.successFg ?? const Color(0xFF166534);
    final errBg = semantic?.errorBg ?? const Color(0xFFFDECEC);
    final errBorder = semantic?.errorBorder ?? const Color(0xFFF1A3A3);
    final errFg = semantic?.errorFg ?? const Color(0xFF9B1C1C);

    final narrowKpi = constraints.maxWidth < 720;
    final largoComGrafico = constraints.maxWidth >= 1040;

    final kpis = narrowKpi
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kpiTile(
                titulo: 'Total pendente',
                valor: _moeda.format(_kpiPendente),
                bg: infoBg,
                border: infoBorder,
                fg: infoFg,
              ),
              const SizedBox(height: 10),
              _kpiTile(
                titulo: 'Total pago',
                valor: _moeda.format(_kpiPago),
                bg: okBg,
                border: okBorder,
                fg: okFg,
              ),
              const SizedBox(height: 10),
              _kpiTile(
                titulo: 'Total em atraso',
                valor: _moeda.format(_kpiAtrasado),
                bg: errBg,
                border: errBorder,
                fg: errFg,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kpiTile(
                  titulo: 'Total pendente',
                  valor: _moeda.format(_kpiPendente),
                  bg: infoBg,
                  border: infoBorder,
                  fg: infoFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiTile(
                  titulo: 'Total pago',
                  valor: _moeda.format(_kpiPago),
                  bg: okBg,
                  border: okBorder,
                  fg: okFg,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiTile(
                  titulo: 'Total em atraso',
                  valor: _moeda.format(_kpiAtrasado),
                  bg: errBg,
                  border: errBorder,
                  fg: errFg,
                ),
              ),
            ],
          );

    final grafico = GraficoVencimentosContasPagar(
      buckets: _buckets,
      saldoCaixaAtual: widget.saldoCaixaReferencia,
    );

    if (largoComGrafico) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: kpis),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: grafico),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        kpis,
        const SizedBox(height: 14),
        grafico,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas a pagar'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tableMinWidth =
              (constraints.maxWidth - 32).clamp(600.0, 4000.0);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPainelTopoKpisEGrafico(context, constraints),
                const SizedBox(height: 18),
                Text(
                  'Filtro por status',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: _filtro == _FiltroStatusConta.todos,
                      onSelected: (_) {
                        setState(() => _filtro = _FiltroStatusConta.todos);
                        _recarregar();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Pendentes'),
                      selected: _filtro == _FiltroStatusConta.pendentes,
                      onSelected: (_) {
                        setState(() => _filtro = _FiltroStatusConta.pendentes);
                        _recarregar();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Pagos'),
                      selected: _filtro == _FiltroStatusConta.pagos,
                      onSelected: (_) {
                        setState(() => _filtro = _FiltroStatusConta.pagos);
                        _recarregar();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Atrasados'),
                      selected: _filtro == _FiltroStatusConta.atrasados,
                      onSelected: (_) {
                        setState(() => _filtro = _FiltroStatusConta.atrasados);
                        _recarregar();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: _linhas.isEmpty
                        ? Center(
                            child: Text(
                              'Nenhuma conta encontrada para este filtro.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : Scrollbar(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: tableMinWidth,
                                ),
                                child: DataTable(
                                  headingRowHeight: 44,
                                  dataRowMinHeight: 48,
                                  columnSpacing: 20,
                                  columns: const [
                                    DataColumn(label: Text('Fornecedor')),
                                    DataColumn(label: Text('NF / ref.')),
                                    DataColumn(label: Text('Parcela')),
                                    DataColumn(label: Text('Emissão')),
                                    DataColumn(label: Text('Vencimento')),
                                    DataColumn(
                                      label: Text('Valor'),
                                      numeric: true,
                                    ),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Ações')),
                                  ],
                                  rows: [
                                    for (final conta in _linhas)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            Text(_nomeFornecedor(conta)),
                                          ),
                                          DataCell(
                                            Text(
                                              conta.nfeChave != null &&
                                                      conta.nfeChave!.length >= 8
                                                  ? '${conta.nfeChave!.substring(0, 8)}…'
                                                  : (conta.numeroNota ??
                                                      'Manual'),
                                            ),
                                          ),
                                          DataCell(Text(conta.numeroParcela)),
                                          DataCell(
                                            Text(
                                              _dataFmt.format(conta.dataEmissao),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              _dataFmt
                                                  .format(conta.dataVencimento),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              _moeda.format(conta.valorParcela),
                                            ),
                                          ),
                                          DataCell(
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: _StatusBadge(
                                                status: conta.status,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            conta.status ==
                                                    ContaPagarStatus.pago
                                                ? const Text(
                                                    '—',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                  )
                                                : OutlinedButton.icon(
                                                    onPressed: () =>
                                                        _confirmarBaixa(conta),
                                                    icon: const Icon(
                                                      Icons.check_circle_outline,
                                                      size: 18,
                                                    ),
                                                    label: const Text(
                                                      'Dar baixa',
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late Color bg;
    late Color fg;
    late String label;
    switch (status) {
      case ContaPagarStatus.pago:
        bg = const Color(0xFFEAF8EF);
        fg = const Color(0xFF166534);
        label = 'Pago';
        break;
      case ContaPagarStatus.atrasado:
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFF9B1C1C);
        label = 'Atrasado';
        break;
      default:
        bg = const Color(0xFFEAF2FF);
        fg = const Color(0xFF1E3A8A);
        label = 'Pendente';
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: bg,
      side: BorderSide(color: fg.withValues(alpha: 0.35)),
    );
  }
}

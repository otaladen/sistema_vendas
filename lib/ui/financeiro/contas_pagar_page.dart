import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/conta_pagar_repository.dart';
import '../../data/models/conta_pagar.dart';
import '../../data/objectbox.dart';
import '../../domain/filtro_contas_pagar.dart';
import '../../main.dart';
import 'widgets/grafico_vencimentos.dart';

final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
final DateFormat _dataFmt = DateFormat('dd/MM/yyyy');

enum _FiltroStatusConta {
  todos,
  pendentes,
  pagos,
  atrasados;

  static _FiltroStatusConta de(FiltroContasPagar f) {
    switch (f) {
      case FiltroContasPagar.todos:
        return _FiltroStatusConta.todos;
      case FiltroContasPagar.pendentes:
        return _FiltroStatusConta.pendentes;
      case FiltroContasPagar.pagos:
        return _FiltroStatusConta.pagos;
      case FiltroContasPagar.atrasados:
        return _FiltroStatusConta.atrasados;
    }
  }
}

/// Listagem de contas a pagar com KPIs, filtros por status e baixa rápida.
class ContasPagarPage extends StatefulWidget {
  const ContasPagarPage({
    super.key,
    required this.objectBox,
    this.saldoCaixaReferencia,
    this.filtroInicial = FiltroContasPagar.todos,
  });

  final ObjectBox objectBox;

  /// Saldo em caixa para linha de referência no gráfico (opcional).
  final double? saldoCaixaReferencia;
  final FiltroContasPagar filtroInicial;

  @override
  State<ContasPagarPage> createState() => _ContasPagarPageState();
}

class _ContasPagarPageState extends State<ContasPagarPage> {
  late ContaPagarRepository _repo;
  late _FiltroStatusConta _filtro;
  List<ContaPagar> _linhas = [];
  ContasPagarVencimentosBuckets _buckets = ContasPagarVencimentosBuckets.zero;

  @override
  void initState() {
    super.initState();
    _repo = ContaPagarRepository(widget.objectBox);
    _filtro = _FiltroStatusConta.de(widget.filtroInicial);
    _recarregar();
  }

  String? _statusQuery(_FiltroStatusConta f) {
    switch (f) {
      case _FiltroStatusConta.todos:
        return null;
      case _FiltroStatusConta.pendentes:
        return ContaPagarStatus.pendente;
      case _FiltroStatusConta.pagos:
        return ContaPagarStatus.pago;
      case _FiltroStatusConta.atrasados:
        return ContaPagarStatus.atrasado;
    }
  }

  void _recarregar() {
    _repo.sincronizarPendenteParaAtrasado();
    final buckets = computeContasPagarVencimentosBuckets(
      widget.objectBox.contaPagarBox,
    );
    final status = _statusQuery(_filtro);
    final lista = _repo.listar(
      status: status,
      ordenarDesc: _filtro == _FiltroStatusConta.pagos,
    );
    if (!mounted) return;
    setState(() {
      _linhas = lista;
      _buckets = buckets;
    });
  }

  double get _kpiPendente => _repo.somaPorStatus(ContaPagarStatus.pendente);
  double get _kpiPago => _repo.somaTotalPago();
  double get _kpiAtrasado => _repo.somaPorStatus(ContaPagarStatus.atrasado);

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

    await _repo.registrarBaixa(
      conta: conta,
      valorPago: vp,
      dataPagamento: dataPg,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pagamento registrado.')),
    );
    _recarregar();
  }

  Future<void> _abrirLancamentoManual() async {
    final fornCtrl = TextEditingController();
    final cnpjCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final parcelaCtrl = TextEditingController(text: '001/001');
    final obsCtrl = TextEditingController();
    var vencimento = DateTime.now().add(const Duration(days: 7));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nova despesa / conta manual'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fornCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Fornecedor / descricao *',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cnpjCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CNPJ (opcional)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor *',
                    prefixText: r'R$ ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: parcelaCtrl,
                  decoration: const InputDecoration(labelText: 'Parcela'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vencimento'),
                  subtitle: Text(_dataFmt.format(vencimento)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: vencimento,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setLocal(() => vencimento = picked);
                    },
                  ),
                ),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia / observacao',
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) {
      fornCtrl.dispose();
      cnpjCtrl.dispose();
      valorCtrl.dispose();
      parcelaCtrl.dispose();
      obsCtrl.dispose();
      return;
    }

    final nome = fornCtrl.text.trim();
    final cnpj = cnpjCtrl.text.trim();
    final valor = double.tryParse(
      valorCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.'),
    );
    final parcela = parcelaCtrl.text.trim();
    final obs = obsCtrl.text.trim();
    fornCtrl.dispose();
    cnpjCtrl.dispose();
    valorCtrl.dispose();
    parcelaCtrl.dispose();
    obsCtrl.dispose();

    if (nome.isEmpty || valor == null || valor <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe fornecedor e valor valido.')),
      );
      return;
    }

    try {
      await _repo.criarManual(
        nomeFornecedor: nome,
        cnpj: cnpj.isEmpty ? null : cnpj,
        valor: valor,
        vencimento: vencimento,
        numeroParcela: parcela.isEmpty ? '001/001' : parcela,
        observacaoNota: obs.isEmpty ? null : obs,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta a pagar registrada.')),
      );
      _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel salvar: $e')),
      );
    }
  }

  Future<void> _exportarCsv() async {
    final pasta = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pasta para salvar CSV de contas a pagar',
    );
    if (pasta == null || pasta.trim().isEmpty) return;

    final todas = _repo.listar();
    final buf = StringBuffer(
      'Fornecedor;NF_ref;Parcela;Emissao;Vencimento;Valor;Status;Pago_em;Valor_pago\n',
    );
    for (final c in todas) {
      buf.writeln([
        _csv(_nomeFornecedor(c)),
        _csv(c.numeroNota ?? c.nfeChave ?? ''),
        _csv(c.numeroParcela),
        _dataFmt.format(c.dataEmissao),
        _dataFmt.format(c.dataVencimento),
        c.valorParcela.toStringAsFixed(2).replaceAll('.', ','),
        c.status,
        c.dataPagamento != null ? _dataFmt.format(c.dataPagamento!) : '',
        c.valorPago?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
      ].join(';'));
    }

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path = p.join(pasta, 'contas_a_pagar_$ts.csv');
    await File(path).writeAsString(buf.toString(), encoding: utf8);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV salvo: $path')),
    );
  }

  String _csv(String v) => '"${v.replaceAll('"', '""')}"';

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
            tooltip: 'Exportar CSV',
            onPressed: _exportarCsv,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirLancamentoManual,
        icon: const Icon(Icons.add),
        label: const Text('Despesa manual'),
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

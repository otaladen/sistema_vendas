import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../model/item_nota_temporario.dart';

/// Resumo financeiro da NF-e (parcelas do XML) na conferencia.
class ConferenciaNfeFinanceiroPainel extends StatefulWidget {
  const ConferenciaNfeFinanceiroPainel({
    super.key,
    required this.duplicatas,
    required this.valorTotalNota,
    this.onDuplicatasChanged,
  });

  final List<NfeDuplicataXml> duplicatas;
  final double valorTotalNota;
  final ValueChanged<List<NfeDuplicataXml>>? onDuplicatasChanged;

  @override
  State<ConferenciaNfeFinanceiroPainel> createState() =>
      _ConferenciaNfeFinanceiroPainelState();
}

class _ConferenciaNfeFinanceiroPainelState
    extends State<ConferenciaNfeFinanceiroPainel> {
  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _nfData = DateFormat('dd/MM/yyyy');

  late List<NfeDuplicataXml> _duplicatas;
  late List<TextEditingController> _valorCtrls;

  @override
  void initState() {
    super.initState();
    _duplicatas = List<NfeDuplicataXml>.from(widget.duplicatas);
    _valorCtrls = _duplicatas
        .map((d) => TextEditingController(text: _nfMoeda.format(d.valorParcela)))
        .toList();
  }

  @override
  void didUpdateWidget(covariant ConferenciaNfeFinanceiroPainel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duplicatas != widget.duplicatas) {
      for (final c in _valorCtrls) {
        c.dispose();
      }
      _duplicatas = List<NfeDuplicataXml>.from(widget.duplicatas);
      _valorCtrls = _duplicatas
          .map(
            (d) => TextEditingController(text: _nfMoeda.format(d.valorParcela)),
          )
          .toList();
    }
  }

  @override
  void dispose() {
    for (final c in _valorCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _notificar() {
    widget.onDuplicatasChanged?.call(
      List<NfeDuplicataXml>.unmodifiable(_duplicatas),
    );
  }

  Future<void> _alterarVencimento(int index) async {
    final atual = _duplicatas[index].dataVencimento;
    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Vencimento da parcela',
    );
    if (escolhida == null || !mounted) return;
    setState(() {
      _duplicatas[index] = _duplicatas[index].copyWith(
        dataVencimento: DateTime(
          escolhida.year,
          escolhida.month,
          escolhida.day,
        ),
      );
    });
    _notificar();
  }

  void _alterarValor(int index, String texto) {
    final valor = _parseMoeda(texto);
    if (valor == null || valor < 0) return;
    _duplicatas[index] = _duplicatas[index].copyWith(valorParcela: valor);
    _notificar();
  }

  static double? _parseMoeda(String texto) {
    final normalizado = texto.trim().replaceAll('.', '').replaceAll(',', '.');
    if (normalizado.isEmpty) return null;
    return double.tryParse(normalizado);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dups = _duplicatas;
    final total = widget.valorTotalNota;
    final totalParcelas =
        dups.fold<double>(0, (s, d) => s + d.valorParcela);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  'Financeiro da nota',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text(
                  'R\$ ${_nfMoeda.format(total)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.tertiary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (dups.isEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sem parcelas no XML — sera lancado como pagamento a vista '
                        '(R\$ ${_nfMoeda.format(total)}).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                'Ajuste vencimento ou valor antes de confirmar, se necessario.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              if ((totalParcelas - total).abs() > 0.05)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(
                    'Soma das parcelas: R\$ ${_nfMoeda.format(totalParcelas)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 56,
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Parcela')),
                    DataColumn(label: Text('Vencimento')),
                    DataColumn(label: Text('Valor'), numeric: true),
                  ],
                  rows: [
                    for (var i = 0; i < dups.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text(dups[i].numeroParcela)),
                          DataCell(
                            InkWell(
                              onTap: () => _alterarVencimento(i),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _nfData.format(dups[i].dataVencimento),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.edit_calendar_outlined,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: _valorCtrls[i],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  prefixText: 'R\$ ',
                                ),
                                onChanged: (v) {
                                  final valor = _parseMoeda(v);
                                  if (valor == null || valor < 0) return;
                                  setState(() {
                                    _duplicatas[i] = _duplicatas[i]
                                        .copyWith(valorParcela: valor);
                                  });
                                  _notificar();
                                },
                                onSubmitted: (v) => _alterarValor(i, v),
                                onEditingComplete: () =>
                                    _alterarValor(i, _valorCtrls[i].text),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../model/item_nota_temporario.dart';

/// Resumo financeiro da NF-e (parcelas do XML) na conferencia.
class ConferenciaNfeFinanceiroPainel extends StatelessWidget {
  const ConferenciaNfeFinanceiroPainel({
    super.key,
    required this.nfe,
  });

  final NfeXmlParseResult nfe;

  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _nfData = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dups = nfe.duplicatas;
    final total = nfe.valorTotalNota;
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
              if ((totalParcelas - total).abs() > 0.05)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Parcela')),
                    DataColumn(label: Text('Vencimento')),
                    DataColumn(label: Text('Valor'), numeric: true),
                  ],
                  rows: [
                    for (final d in dups)
                      DataRow(
                        cells: [
                          DataCell(Text(d.numeroParcela)),
                          DataCell(
                            Text(_nfData.format(d.dataVencimento.toLocal())),
                          ),
                          DataCell(
                            Text('R\$ ${_nfMoeda.format(d.valorParcela)}'),
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

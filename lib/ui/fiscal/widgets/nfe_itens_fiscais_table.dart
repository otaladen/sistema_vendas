import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/fiscal/nfe_item_fiscal_preview.dart';

/// Grade de itens com NCM, CFOP, CST e alertas fiscais.
class NfeItensFiscaisTable extends StatelessWidget {
  const NfeItensFiscaisTable({
    super.key,
    required this.linhas,
    this.onAbrirProduto,
  });

  final List<NfeItemFiscalPreview> linhas;
  final void Function(int produtoId)? onAbrirProduto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');

    if (linhas.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhum item fiscal para exibir.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart_outlined,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Itens fiscais', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 96,
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Descricao')),
                  DataColumn(label: Text('Qtd'), numeric: true),
                  DataColumn(label: Text('NCM')),
                  DataColumn(label: Text('CEST')),
                  DataColumn(label: Text('Grupo')),
                  DataColumn(label: Text('CFOP')),
                  DataColumn(label: Text('ICMS')),
                  DataColumn(label: Text('PIS')),
                  DataColumn(label: Text('GTIN')),
                  DataColumn(label: Text('Alertas')),
                ],
                rows: linhas.map((l) {
                  final temErro = l.bloqueiaEmissao;
                  return DataRow(
                    color: temErro
                        ? WidgetStatePropertyAll(
                            theme.colorScheme.errorContainer
                                .withValues(alpha: 0.35),
                          )
                        : null,
                    cells: [
                      DataCell(Text('${l.numero}')),
                      DataCell(
                        l.produtoId > 0 && onAbrirProduto != null
                            ? InkWell(
                                onTap: () => onAbrirProduto!(l.produtoId),
                                child: Text(
                                  l.codigo,
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              )
                            : Text(l.codigo),
                      ),
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            l.descricao,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text('${l.quantidade}')),
                      DataCell(Text(l.ncm.isEmpty ? '-' : l.ncm)),
                      DataCell(Text(l.cest.isEmpty ? '-' : l.cest)),
                      DataCell(Text(l.grupoRotulo)),
                      DataCell(
                        Text(
                          l.cfop,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(l.icmsCst)),
                      DataCell(Text(l.pisCofinsCst)),
                      DataCell(
                        Text(
                          l.gtin,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      DataCell(
                        l.alertas.isEmpty
                            ? const Icon(Icons.check, size: 18, color: Colors.green)
                            : SizedBox(
                                width: 180,
                                child: Text(
                                  l.alertas.join(' '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: temErro
                                        ? theme.colorScheme.error
                                        : Colors.orange.shade900,
                                  ),
                                  maxLines: 3,
                                ),
                              ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Subtotal itens: R\$ ${moeda.format(linhas.fold<double>(0, (s, l) => s + l.subtotal))}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

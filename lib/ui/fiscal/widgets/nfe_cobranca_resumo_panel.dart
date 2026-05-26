import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/fiscal/nfe_cobranca_helper.dart';
import '../../../model/venda.dart';

/// Resumo de fatura/duplicatas que irao na NF-e.
class NfeCobrancaResumoPanel extends StatelessWidget {
  const NfeCobrancaResumoPanel({
    super.key,
    required this.venda,
    required this.valorCobranca,
  });

  final Venda venda;
  final double valorCobranca;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');

    if (!NfeCobrancaHelper.vendaExigeBlocoCobranca(venda) || valorCobranca <= 0) {
      return const SizedBox.shrink();
    }

    final parcelas = NfeCobrancaHelper.resolverParcelas(venda, valorCobranca);
    final dataFmt = DateFormat('dd/MM/yyyy');

    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 22, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Cobranca na NF-e', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Forma: ${venda.formaPagamento} · '
              'Valor a prazo: R\$ ${moeda.format(valorCobranca)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (parcelas.isEmpty)
              Text(
                'Parcelas nao definidas — corrija no PDV.',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(0.6),
                  1: FlexColumnWidth(1.2),
                  2: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor,
                        ),
                      ),
                    ),
                    children: [
                      _th(theme, 'Parc.'),
                      _th(theme, 'Vencimento'),
                      _th(theme, 'Valor', align: TextAlign.right),
                    ],
                  ),
                  ...parcelas.map(
                    (p) => TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('${p.numero}'),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(dataFmt.format(p.vencimento.toLocal())),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'R\$ ${moeda.format(p.valor)}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _th(ThemeData theme, String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: align,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

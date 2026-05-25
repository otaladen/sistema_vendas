import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../model/cliente.dart';
import '../../model/venda.dart';

/// Lista compacta das ultimas vendas finalizadas no painel lateral do caixa.
class CaixaUltimasVendasList extends StatelessWidget {
  const CaixaUltimasVendasList({
    super.key,
    required this.vendas,
    required this.clienteDaVenda,
    required this.formatarMoeda,
    required this.onVendaTap,
  });

  final List<Venda> vendas;
  final Cliente? Function(Venda venda) clienteDaVenda;
  final String Function(double valor) formatarMoeda;
  final void Function(Venda venda) onVendaTap;

  @override
  Widget build(BuildContext context) {
    final dtCurto = DateFormat('dd/MM HH:mm');
    if (vendas.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma venda finalizada ainda.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: vendas.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final v = vendas[index];
            final cliente = clienteDaVenda(v);
            final badge =
                v.numeroOrcamento > 0 ? '${v.numeroOrcamento}' : '${v.id}';
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: CircleAvatar(
                radius: 16,
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              title: Text(
                'Venda ${v.numeroOrcamento > 0 ? v.numeroOrcamento : v.id}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Text(
                '${dtCurto.format(v.data.toLocal())} · '
                '${cliente?.nomeRazao ?? 'Sem cliente'} · '
                '${v.itens.length} itens',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v.nfceEmitida)
                    Tooltip(
                      message: 'NFC-e emitida',
                      child: Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                    ),
                  if (v.nfceEmitida) const SizedBox(width: 8),
                  Text(
                    formatarMoeda(v.total),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              onTap: () => onVendaTap(v),
            );
          },
        ),
      ),
    );
  }
}

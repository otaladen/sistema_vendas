import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../model/item_nota_temporario.dart';

/// Cabecalho resumo da conferencia NF-e (estilo ERP).
class ConferenciaNfeCabecalho extends StatelessWidget {
  const ConferenciaNfeCabecalho({
    super.key,
    required this.nfe,
    required this.totalItens,
    required this.itensVinculados,
    required this.itensNovos,
    required this.itensAtencao,
  });

  final NfeXmlParseResult nfe;
  final int totalItens;
  final int itensVinculados;
  final int itensNovos;
  final int itensAtencao;

  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');
  static final _nfData = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emit = nfe.emitente;
    final dataEmissao = _nfData.format(nfe.dataEmissao.toLocal());
    final valor = 'R\$ ${_nfMoeda.format(nfe.valorTotalNota)}';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.receipt_long_outlined, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NF-e nº ${nfe.numeroNota} · $dataEmissao',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        emit.razaoSocial,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        'CNPJ ${emit.cnpj}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      valor,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                    ),
                    Text(
                      '$totalItens ${totalItens == 1 ? 'item' : 'itens'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ResumoChip(
                  icon: Icons.inventory_2_outlined,
                  label: '$totalItens itens',
                  color: cs.primary,
                ),
                _ResumoChip(
                  icon: Icons.link,
                  label: '$itensVinculados vinculados',
                  color: cs.tertiary,
                ),
                if (itensNovos > 0)
                  _ResumoChip(
                    icon: Icons.fiber_new_outlined,
                    label: '$itensNovos novos',
                    color: cs.secondary,
                  ),
                if (itensAtencao > 0)
                  _ResumoChip(
                    icon: Icons.warning_amber_rounded,
                    label: '$itensAtencao atenção',
                    color: cs.error,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Chave ${nfe.chaveAcesso}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoChip extends StatelessWidget {
  const _ResumoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

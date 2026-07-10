import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Rodape fixo da conferencia NF-e com resumo e confirmacao.
class ConferenciaNfeRodape extends StatelessWidget {
  const ConferenciaNfeRodape({
    super.key,
    required this.totalItens,
    required this.itensProntos,
    required this.valorTotalNota,
    required this.confirmando,
    required this.onConfirmar,
  });

  final int totalItens;
  final int itensProntos;
  final double valorTotalNota;
  final bool confirmando;
  final VoidCallback onConfirmar;

  static final _nfMoeda = NumberFormat('#,##0.00', 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todosProntos = itensProntos >= totalItens && totalItens > 0;
    final valor = 'R\$ ${_nfMoeda.format(valorTotalNota)}';

    return Material(
      elevation: 8,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$itensProntos de $totalItens itens conferidos',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      'Total da nota: $valor',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    if (!todosProntos)
                      Text(
                        'Revise itens novos, vinculos e fatores antes de confirmar.',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.tertiary,
                            ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: confirmando ? null : onConfirmar,
                icon: confirmando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  confirmando ? 'Gravando...' : 'Confirmar entrada (F10)',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

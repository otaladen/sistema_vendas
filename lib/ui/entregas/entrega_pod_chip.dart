import 'package:flutter/material.dart';

import '../../domain/entrega_pod_regra.dart';
import '../../model/venda.dart';

/// Indicador compacto de POD (lista, Kanban, etc.).
class EntregaPodChip extends StatelessWidget {
  const EntregaPodChip({
    super.key,
    required this.venda,
    this.compacto = false,
  });

  final Venda venda;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    if (!EntregaPodRegra.temPodRegistrado(venda.podRecebidoPor)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final comFoto = EntregaPodRegra.temReferenciaFoto(
      podFotoPath: venda.podFotoPath,
      podFotoPathServidor: venda.podFotoPathServidor,
    );
    final cor = scheme.tertiary;

    return Tooltip(
      message: comFoto
          ? 'POD: ${venda.podRecebidoPor} (com foto)'
          : 'POD: ${venda.podRecebidoPor}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 8 : 10,
          vertical: compacto ? 2 : 4,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: cor.withValues(alpha: 0.12),
          border: Border.all(color: cor.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              comFoto ? Icons.verified_outlined : Icons.how_to_reg_outlined,
              size: compacto ? 14 : 16,
              color: cor,
            ),
            const SizedBox(width: 4),
            Text(
              compacto ? 'POD' : 'POD ok',
              style: TextStyle(
                fontSize: compacto ? 11 : 12,
                color: cor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

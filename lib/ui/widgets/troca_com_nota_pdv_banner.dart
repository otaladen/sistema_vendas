import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/troca_com_nota_pdv_intent.dart';

/// Banner no PDV quando aberto apos devolucao (troca com nota).
class TrocaComNotaPdvBanner extends StatelessWidget {
  const TrocaComNotaPdvBanner({
    super.key,
    required this.intent,
    required this.creditoAplicadoNoDesconto,
    required this.maxDescontoPermitidoReais,
    required this.onFechar,
  });

  final TrocaComNotaPdvIntent intent;
  final double? creditoAplicadoNoDesconto;
  final double maxDescontoPermitidoReais;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final moeda = NumberFormat('#,##0.00', 'pt_BR');
    final refVenda = intent.numeroVendaOrigem > 0
        ? 'venda ${intent.numeroVendaOrigem}'
        : 'venda id ${intent.vendaOrigemId}';
    final creditoFmt = 'R\$ ${moeda.format(intent.creditoDevolucaoReais)}';

    String detalheDesconto;
    if (creditoAplicadoNoDesconto != null && creditoAplicadoNoDesconto! > 0) {
      detalheDesconto =
          'Desconto F3 preenchido com R\$ ${moeda.format(creditoAplicadoNoDesconto!)} '
          '(credito da devolucao).';
      if (intent.creditoDevolucaoReais > creditoAplicadoNoDesconto! + 0.01) {
        detalheDesconto +=
            ' Parte do credito (${moeda.format(intent.creditoDevolucaoReais - creditoAplicadoNoDesconto!)}) '
            'excede o teto do PDV — combine com o gerente.';
      }
    } else if (maxDescontoPermitidoReais <= 0) {
      detalheDesconto =
          'Seu usuario nao tem desconto no PDV. Credito sugerido: $creditoFmt — '
          'registre na observacao do orcamento ou ajuste com gerente.';
    } else {
      detalheDesconto =
          'Ao incluir produtos novos, o desconto (F3) sera sugerido ate '
          'R\$ ${moeda.format(maxDescontoPermitidoReais.clamp(0, intent.creditoDevolucaoReais))} '
          '(credito $creditoFmt da $refVenda).';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: tema.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.swap_horiz, color: tema.colorScheme.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Troca com nota — produtos novos',
                    style: tema.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1) Inclua aqui somente o que o cliente leva agora.\n'
                    '2) $detalheDesconto\n'
                    '3) F10 enviar ao caixa e emitir cupom/NFC-e/NF-e na venda nova.',
                    style: tema.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Ocultar aviso',
              onPressed: onFechar,
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

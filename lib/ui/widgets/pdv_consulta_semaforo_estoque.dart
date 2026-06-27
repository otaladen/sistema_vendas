import 'package:flutter/material.dart';

import '../../domain/pdv_estoque_semaforo_util.dart';
import '../../model/produto.dart';

/// Semafaro compacto (cor + quantidade) para a lista da consulta PDV.
class PdvConsultaSemaforoEstoque extends StatelessWidget {
  const PdvConsultaSemaforoEstoque({
    super.key,
    required this.produto,
    this.quantidadeNoOrcamento = 0,
    this.mostrarNumero = true,
  });

  final Produto produto;
  final int quantidadeNoOrcamento;
  final bool mostrarNumero;

  @override
  Widget build(BuildContext context) {
    final disponivel = produto.estoqueLivreParaVenda;
    final nivel = PdvEstoqueSemaforoUtil.nivelDe(
      produto,
      quantidadeNoOrcamento: quantidadeNoOrcamento,
    );
    final cor = PdvEstoqueSemaforoUtil.corDe(context, nivel);
    final tooltip = PdvEstoqueSemaforoUtil.tooltipDe(
      produto,
      quantidadeNoOrcamento: quantidadeNoOrcamento,
    );

    return Tooltip(
      message: tooltip,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cor.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 9, color: cor),
              if (mostrarNumero) ...[
                const SizedBox(width: 4),
                Text(
                  '$disponivel',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cor,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

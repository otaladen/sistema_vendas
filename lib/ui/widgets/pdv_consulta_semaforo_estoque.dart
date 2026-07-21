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
    this.nivelPrecalculado,
  });

  final Produto produto;
  final num quantidadeNoOrcamento;
  final bool mostrarNumero;
  final PdvEstoqueSemaforoNivel? nivelPrecalculado;

  @override
  Widget build(BuildContext context) {
    final disponivel = produto.estoqueLivreParaVenda;
    final nivel = nivelPrecalculado ??
        PdvEstoqueSemaforoUtil.nivelDe(
          produto,
          quantidadeNoOrcamento: quantidadeNoOrcamento,
        );
    final cor = PdvEstoqueSemaforoUtil.corDe(context, nivel);
    final tooltip = PdvEstoqueSemaforoUtil.tooltipDe(
      produto,
      quantidadeNoOrcamento: quantidadeNoOrcamento,
    );
    final scheme = Theme.of(context).colorScheme;
    final rotulo = PdvEstoqueSemaforoUtil.rotuloQuantidadeLista(
      produto,
      disponivel,
    );
    final estiloNumero = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          height: 1.1,
        );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
              ),
            ),
            if (mostrarNumero) ...[
              const SizedBox(width: 5),
              Text(
                rotulo,
                maxLines: 1,
                style: estiloNumero,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

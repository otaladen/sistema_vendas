import 'package:flutter/material.dart';

import '../../domain/entrega_nao_entregue.dart';
import '../../model/venda.dart';

/// Faixa compacta do insucesso no patio (motivo + carga).
class EntregaInsucessoFaixa extends StatelessWidget {
  const EntregaInsucessoFaixa({
    super.key,
    required this.venda,
    this.padding = const EdgeInsets.only(top: 4),
  });

  final Venda venda;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final resumo = EntregaInsucessoResumo.deVenda(
      statusEntrega: venda.statusEntrega,
      observacaoEntrega: venda.observacaoEntrega,
    );
    if (resumo == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(
        resumo.linhaPatio,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.orange.shade800,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

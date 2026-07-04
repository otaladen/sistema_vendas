import 'package:flutter/material.dart';

import '../../model/venda.dart';

/// Dados prontos para exibir uma venda na listagem (tabela ou card).
class ListagemVendaItemUi {
  const ListagemVendaItemUi({
    required this.venda,
    required this.titulo,
    required this.status,
    required this.statusCor,
    required this.dataHora,
    required this.cliente,
    required this.vendedor,
    required this.pagamento,
    required this.entrega,
    required this.badgeNumero,
    required this.totalFormatado,
    required this.cancelada,
    this.statusDetalhe,
    this.alertas = const [],
  });

  final Venda venda;
  final String titulo;
  final String status;
  final Color statusCor;
  final String dataHora;
  final String cliente;
  final String vendedor;
  final String pagamento;
  final String entrega;
  final String badgeNumero;
  final String totalFormatado;
  final bool cancelada;
  /// Texto completo do status (tooltip na tabela).
  final String? statusDetalhe;
  final List<String> alertas;
}

import 'package:flutter/material.dart';

import 'tipo_movimento_estoque.dart';

/// Agrupa o kardex para filtro visual (entrada, saida, so reserva).
enum NaturezaKardex { entrada, saida, reserva, neutro }

/// Rotulos e utilidades do kardex de estoque.
abstract final class MovimentoEstoqueHelper {
  static String rotuloTipo(String tipoMovimento) {
    for (final t in TipoMovimentoEstoque.values) {
      if (t.name == tipoMovimento) return rotuloTipoEnum(t);
    }
    return tipoMovimento.isEmpty ? 'Movimento' : tipoMovimento;
  }

  static String rotuloTipoEnum(TipoMovimentoEstoque tipo) {
    switch (tipo) {
      case TipoMovimentoEstoque.orcamentoReserva:
        return 'Reserva orcamento';
      case TipoMovimentoEstoque.orcamentoLiberaReserva:
        return 'Libera reserva orcamento';
      case TipoMovimentoEstoque.finalizacaoAjustaReserva:
        return 'Ajuste reserva caixa';
      case TipoMovimentoEstoque.cupomNaoFiscalVenda:
        return 'Cupom nao fiscal (retirada)';
      case TipoMovimentoEstoque.entradaNfeCompra:
        return 'Entrada NF-e compra';
      case TipoMovimentoEstoque.estornoEntradaNfeCompra:
        return 'Estorno entrada NF-e';
      case TipoMovimentoEstoque.carretoSaida:
        return 'Saida carreto';
      case TipoMovimentoEstoque.carretoEstornoSaida:
        return 'Estorno saida carreto';
      case TipoMovimentoEstoque.retiradaParcialCliente:
        return 'Retirada parcial cliente';
      case TipoMovimentoEstoque.retiradaTotalImediata:
        return 'Retirada total imediata';
      case TipoMovimentoEstoque.complementoEntregaFalta:
        return 'Complemento entrega (falta)';
      case TipoMovimentoEstoque.complementoEntregaBaixa:
        return 'Baixa complemento entrega';
      case TipoMovimentoEstoque.cancelamentoVendaEstorno:
        return 'Estorno cancelamento venda';
      case TipoMovimentoEstoque.devolucaoCliente:
        return 'Devolucao / troca';
      case TipoMovimentoEstoque.devolucaoFornecedor:
        return 'Devolucao ao fornecedor';
      case TipoMovimentoEstoque.ajusteManual:
        return 'Ajuste manual';
      case TipoMovimentoEstoque.vendaDiretaLegada:
        return 'Venda direta (legado)';
      case TipoMovimentoEstoque.nfceEmissao:
        return 'NFC-e (sem estoque)';
      case TipoMovimentoEstoque.nfeVendaEmissao:
        return 'NF-e venda (sem estoque)';
    }
  }

  static String formatarDelta(int delta) {
    if (delta > 0) return '+$delta';
    return '$delta';
  }

  static NaturezaKardex natureza({
    required int deltaFisico,
    required int deltaReserva,
  }) {
    if (deltaFisico > 0) return NaturezaKardex.entrada;
    if (deltaFisico < 0) return NaturezaKardex.saida;
    if (deltaReserva != 0) return NaturezaKardex.reserva;
    return NaturezaKardex.neutro;
  }

  static IconData iconeTipo(String tipoMovimento) {
    switch (tipoMovimento) {
      case 'entradaNfeCompra':
        return Icons.move_to_inbox_outlined;
      case 'estornoEntradaNfeCompra':
      case 'cancelamentoVendaEstorno':
      case 'carretoEstornoSaida':
        return Icons.undo_rounded;
      case 'carretoSaida':
        return Icons.local_shipping_outlined;
      case 'cupomNaoFiscalVenda':
      case 'retiradaParcialCliente':
      case 'retiradaTotalImediata':
      case 'vendaDiretaLegada':
        return Icons.point_of_sale_outlined;
      case 'orcamentoReserva':
      case 'orcamentoLiberaReserva':
      case 'finalizacaoAjustaReserva':
        return Icons.bookmark_outline;
      case 'ajusteManual':
        return Icons.tune;
      case 'devolucaoCliente':
      case 'devolucaoFornecedor':
        return Icons.assignment_return_outlined;
      case 'complementoEntregaFalta':
      case 'complementoEntregaBaixa':
        return Icons.add_shopping_cart_outlined;
      default:
        return Icons.swap_vert_rounded;
    }
  }
}

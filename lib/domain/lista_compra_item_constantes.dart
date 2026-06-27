/// Status operacional de um item na lista de compras.
abstract final class ListaCompraItemStatus {
  static const pendente = 'pendente';
  static const cotacao = 'cotacao';
  static const pedido = 'pedido';
  static const recebido = 'recebido';
  static const cancelado = 'cancelado';

  static const ativos = [pendente, cotacao, pedido];

  static String rotulo(String status) {
    switch (status) {
      case cotacao:
        return 'Em cotacao';
      case pedido:
        return 'Pedido feito';
      case recebido:
        return 'Recebido';
      case cancelado:
        return 'Cancelado';
      case pendente:
      default:
        return 'Pendente';
    }
  }
}

/// Origem do item na lista.
abstract final class ListaCompraItemOrigem {
  static const manual = 'manual';
  static const sistema = 'sistema';
  static const vendaPerdida = 'venda_perdida';

  static String rotulo(String origem) {
    switch (origem) {
      case sistema:
        return 'Sistema';
      case vendaPerdida:
        return 'Venda sem estoque';
      case manual:
      default:
        return 'Manual';
    }
  }
}

/// Prioridade para o comprador.
abstract final class ListaCompraItemPrioridade {
  static const normal = 'normal';
  static const urgente = 'urgente';

  static String rotulo(String prioridade) =>
      prioridade == urgente ? 'Urgente' : 'Normal';
}

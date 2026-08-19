/// Conflito de estado terminal (entregue / cancelada / cruzamento atrasado).
class EntregaStatusConflitoException implements Exception {
  EntregaStatusConflitoException(
    this.message, {
    this.code = codigoTerminal,
  });

  static const codigoTerminal = 'entrega_status_terminal';

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// Impede last-write-wins entre Entregue e Reagendada no servidor.
abstract final class EntregaStatusTransicao {
  EntregaStatusTransicao._();

  static bool ehTerminal(String status) {
    switch (status.trim()) {
      case 'entregue':
      case 'cancelada':
        return true;
      default:
        return false;
    }
  }

  /// Null = permitido (incluindo idempotente: atual == novo).
  static String? mensagemBloqueio(String atual, String novo) {
    final a = atual.trim();
    final n = novo.trim();
    if (a == n) return null;

    if (a == 'entregue') {
      if (n == 'reagendada') {
        return 'Entrega ja foi marcada como entregue. '
            'Uma baixa atrasada de insucesso foi ignorada.';
      }
      return 'Entrega ja foi marcada como entregue. '
          'Nao e possivel alterar o status.';
    }
    if (a == 'cancelada') {
      return 'Entrega cancelada. Status nao pode ser alterado.';
    }
    if (a == 'reagendada' && n == 'entregue') {
      return 'Entrega ja foi reagendada. '
          'Uma baixa atrasada de "entregue" foi ignorada. '
          'Liberar saida no patio e tentar de novo.';
    }
    return null;
  }

  static void garantirPermitida(String atual, String novo) {
    final msg = mensagemBloqueio(atual, novo);
    if (msg != null) {
      throw EntregaStatusConflitoException(msg);
    }
  }
}

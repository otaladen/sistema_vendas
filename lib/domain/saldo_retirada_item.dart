/// Unica formula do saldo de retirada do cliente.
///
/// Unidades ainda na loja = vendido na nota/orcamento
///   menos ja retirado
///   menos ja devolvido.
/// A quantidade retirada nunca pode ultrapassar o vendido liquido.
abstract final class SaldoRetiradaItem {
  SaldoRetiradaItem._();

  /// Quantidade vendida ainda "na nota" (desconta devolucao/troca).
  static int vendidoLiquido({
    required int quantidade,
    required int quantidadeDevolvida,
  }) {
    final vendido = quantidade < 0 ? 0 : quantidade;
    final devolvida = quantidadeDevolvida < 0 ? 0 : quantidadeDevolvida;
    final liquido = vendido - devolvida;
    return liquido < 0 ? 0 : liquido;
  }

  /// [quantidadeJaRetirada] limitada ao vendido liquido (nunca negativa).
  static int jaRetiradaCapped({
    required int quantidadeJaRetirada,
    required int quantidade,
    required int quantidadeDevolvida,
  }) {
    final ja = quantidadeJaRetirada < 0 ? 0 : quantidadeJaRetirada;
    final teto = vendidoLiquido(
      quantidade: quantidade,
      quantidadeDevolvida: quantidadeDevolvida,
    );
    return ja > teto ? teto : ja;
  }

  /// Unidades que o cliente ainda pode retirar nesta linha.
  static int pendente({
    required int quantidade,
    required int quantidadeJaRetirada,
    required int quantidadeDevolvida,
  }) {
    final liquido = vendidoLiquido(
      quantidade: quantidade,
      quantidadeDevolvida: quantidadeDevolvida,
    );
    final ja = quantidadeJaRetirada < 0 ? 0 : quantidadeJaRetirada;
    final p = liquido - ja;
    return p < 0 ? 0 : p;
  }

  /// Garante que a baixa nao ultrapassa o vendido na nota nem o pendente.
  static void validarRetirada({
    required String nomeProduto,
    required int quantidade,
    required int quantidadeJaRetirada,
    required int quantidadeDevolvida,
    required int quantidadeSolicitada,
  }) {
    if (quantidadeSolicitada <= 0) {
      throw StateError(
        'Quantidade a retirar de "$nomeProduto" deve ser maior que zero.',
      );
    }
    final liquido = vendidoLiquido(
      quantidade: quantidade,
      quantidadeDevolvida: quantidadeDevolvida,
    );
    final ja = quantidadeJaRetirada < 0 ? 0 : quantidadeJaRetirada;
    if (ja + quantidadeSolicitada > liquido) {
      throw StateError(
        'Retirada de $quantidadeSolicitada un. de "$nomeProduto" ultrapassa '
        'o vendido na nota/orcamento ($liquido un. liquido; ja retirado $ja).',
      );
    }
    final p = pendente(
      quantidade: quantidade,
      quantidadeJaRetirada: quantidadeJaRetirada,
      quantidadeDevolvida: quantidadeDevolvida,
    );
    if (quantidadeSolicitada > p) {
      throw StateError(
        'Retirada de $quantidadeSolicitada un. de "$nomeProduto" excede o '
        'pendente ($p).',
      );
    }
  }
}

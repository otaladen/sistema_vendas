import 'troca_diferenca_caixa.dart';

/// Linha de produto de saida na troca (quantidade x preco praticado).
class TrocaSaidaLinhaConferencia {
  const TrocaSaidaLinhaConferencia({
    required this.quantidade,
    required this.precoUnitarioPraticado,
  });

  final int quantidade;
  final double precoUnitarioPraticado;
}

/// Subtotal da saida e diferenca frente ao credito da devolucao.
abstract final class TrocaConferenciaValores {
  TrocaConferenciaValores._();

  static double subtotalSaida(Iterable<TrocaSaidaLinhaConferencia> linhas) {
    var total = 0.0;
    for (final l in linhas) {
      if (l.quantidade <= 0) continue;
      total += l.quantidade * l.precoUnitarioPraticado;
    }
    return TrocaDiferencaCaixa.arredondar(total);
  }

  /// Positivo = cliente paga; negativo = loja devolve.
  static double diferenca({
    required Iterable<TrocaSaidaLinhaConferencia> linhasSaida,
    required double valorDevolvido,
  }) =>
      TrocaDiferencaCaixa.diferenca(
        valorSaida: subtotalSaida(linhasSaida),
        valorDevolvido: valorDevolvido,
      );
}

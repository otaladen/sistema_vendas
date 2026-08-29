/// Diferenca financeira da troca (saida − devolvido) e o uuid do orcamento
/// que vai para o caixa quando o cliente precisa pagar.
abstract final class TrocaDiferencaCaixa {
  TrocaDiferencaCaixa._();

  static const epsilon = 0.009;

  static double arredondar(num v) =>
      ((v.toDouble() * 100).roundToDouble()) / 100;

  /// Positivo = cliente paga; negativo = loja devolve.
  static double diferenca({
    required double valorSaida,
    required double valorDevolvido,
  }) =>
      arredondar(valorSaida - valorDevolvido);

  static bool clientePaga(double diferenca) => diferenca > epsilon;

  static bool lojaDevolve(double diferenca) => diferenca < -epsilon;

  static const meiosPagamento = {
    'dinheiro',
    'pix',
    'cartao_debito',
    'cartao_credito',
  };

  static String normalizarMeio(String? meio) {
    final m = (meio ?? '').trim().toLowerCase();
    return meiosPagamento.contains(m) ? m : 'dinheiro';
  }

  static int parcelasCredito(String meio, int? parcelas) {
    if (normalizarMeio(meio) != 'cartao_credito') return 1;
    final p = parcelas ?? 1;
    if (p < 1) return 1;
    if (p > 12) return 12;
    return p;
  }

  static bool geraNfce(String meio) {
    switch (normalizarMeio(meio)) {
      case 'pix':
      case 'cartao_debito':
      case 'cartao_credito':
        return true;
      default:
        return false;
    }
  }

  static String uuidOrcamento(int registroDevolucaoId) =>
      'complemento-troca-$registroDevolucaoId';
}

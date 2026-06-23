/// Calculo de preco de venda a partir de custo e margem (% sobre o preco).
class ProdutoPrecificacao {
  ProdutoPrecificacao._();

  /// Margem sobre o preco de venda: ((preco - custo) / preco) * 100.
  static double margemSobrePrecoVenda({
    required double custo,
    required double precoVenda,
  }) {
    if (precoVenda <= 0) return 0;
    return ((precoVenda - custo) / precoVenda) * 100;
  }

  /// Preco com margem definida sobre o valor de venda (mesma formula do KPI do cadastro).
  static double precoComMargemSobreVenda({
    required double custo,
    required double margemPercentual,
  }) {
    if (custo < 0) return 0;
    if (margemPercentual <= 0) return custo;
    final m = margemPercentual.clamp(0.0, 99.0);
    return custo / (1 - m / 100);
  }

  /// Markup sobre o custo: ((preco - custo) / custo) * 100.
  static double markupSobreCusto({
    required double custo,
    required double precoVenda,
  }) {
    if (custo <= 0 || precoVenda <= 0) return 0;
    return ((precoVenda - custo) / custo) * 100;
  }

  /// Preco a partir de markup % sobre o custo: custo * (1 + markup/100).
  static double precoComMarkupSobreCusto({
    required double custo,
    required double markupPercentual,
  }) {
    if (custo < 0) return 0;
    if (markupPercentual <= 0) return custo;
    return custo * (1 + markupPercentual.clamp(0.0, 1000.0) / 100);
  }
}

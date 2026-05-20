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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_precificacao.dart';

void main() {
  test('markup e preco com markup sao inversos', () {
    const custo = 145.0;
    const markup = 51.72;
    final preco = ProdutoPrecificacao.precoComMarkupSobreCusto(
      custo: custo,
      markupPercentual: markup,
    );
    expect(preco, closeTo(220, 0.05));
    expect(
      ProdutoPrecificacao.markupSobreCusto(custo: custo, precoVenda: preco),
      closeTo(markup, 0.05),
    );
  });
}

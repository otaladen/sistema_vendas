import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_limite_desconto_pdv.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _prod({
  double lim1 = 0,
  double lim2 = 0,
  double lim3 = 0,
}) {
  return Produto(
    codigoInterno: '1',
    nome: 'Teste',
    quantidadeMinima: 0,
    precoCusto: 10,
    precoVenda: 100,
    limiteDescontoPreco1: lim1,
    limiteDescontoPreco2: lim2,
    limiteDescontoPreco3: lim3,
  );
}

void main() {
  test('usa teto da loja quando cadastro do produto e zero', () {
    final pct = ProdutoLimiteDescontoPdv.percentualEfetivo(
      produto: _prod(),
      precoTipo: 'preco1',
      tetoEmpresaOuUsuario: 15,
    );
    expect(pct, 15);
  });

  test('usa limite do produto quando cadastrado', () {
    final pct = ProdutoLimiteDescontoPdv.percentualEfetivo(
      produto: _prod(lim2: 5),
      precoTipo: 'preco2',
      tetoEmpresaOuUsuario: 15,
    );
    expect(pct, 5);
  });

  test('soma tetos por linha no carrinho misto', () {
    final linhas = [
      LinhaCalculoLimiteDescontoPdv(
        produto: _prod(lim1: 10),
        precoTipo: 'preco1',
        subtotal: 100,
      ),
      LinhaCalculoLimiteDescontoPdv(
        produto: _prod(lim2: 5),
        precoTipo: 'preco2',
        subtotal: 200,
      ),
    ];
    final max = ProdutoLimiteDescontoPdv.valorMaximoDescontoReais(
      linhas: linhas,
      tetoEmpresaOuUsuario: 15,
    );
    expect(max, closeTo(20, 0.001)); // 10 + 10
  });

  test('ignora linhas em promocao', () {
    final linhas = [
      LinhaCalculoLimiteDescontoPdv(
        produto: _prod(lim1: 10),
        precoTipo: 'preco1',
        subtotal: 100,
        promocaoId: 1,
      ),
      LinhaCalculoLimiteDescontoPdv(
        produto: _prod(),
        precoTipo: 'preco1',
        subtotal: 50,
      ),
    ];
    final max = ProdutoLimiteDescontoPdv.valorMaximoDescontoReais(
      linhas: linhas,
      tetoEmpresaOuUsuario: 10,
    );
    expect(max, closeTo(5, 0.001));
  });
}

import '../model/produto.dart';

/// Linha do carrinho/orcamento usada no calculo de teto de desconto.
class LinhaCalculoLimiteDescontoPdv {
  const LinhaCalculoLimiteDescontoPdv({
    required this.produto,
    required this.precoTipo,
    required this.subtotal,
    this.promocaoId = 0,
  });

  final Produto produto;
  final String precoTipo;
  final double subtotal;
  final int promocaoId;
}

/// Teto de desconto no PDV/caixa considerando cadastro do produto por tabela de preco.
class ProdutoLimiteDescontoPdv {
  const ProdutoLimiteDescontoPdv._();

  static double limiteCadastroProduto(Produto produto, String precoTipo) {
    switch (precoTipo) {
      case 'preco2':
        return produto.limiteDescontoPreco2;
      case 'preco3':
        return produto.limiteDescontoPreco3;
      case 'preco1':
      default:
        return produto.limiteDescontoPreco1;
    }
  }

  /// Percentual efetivo da linha: cadastro (>0) ou teto da empresa/usuario.
  static double percentualEfetivo({
    required Produto produto,
    required String precoTipo,
    required double tetoEmpresaOuUsuario,
  }) {
    final cadastro = limiteCadastroProduto(produto, precoTipo);
    if (cadastro > 0.004) return cadastro.clamp(0, 100);
    return tetoEmpresaOuUsuario.clamp(0, 100);
  }

  static double subtotalElegivel(Iterable<LinhaCalculoLimiteDescontoPdv> linhas) {
    return linhas
        .where((l) => l.promocaoId <= 0)
        .fold(0.0, (s, l) => s + l.subtotal);
  }

  /// Soma dos tetos por linha (promocao excluida; frete nao entra).
  static double valorMaximoDescontoReais({
    required Iterable<LinhaCalculoLimiteDescontoPdv> linhas,
    required double tetoEmpresaOuUsuario,
  }) {
    if (tetoEmpresaOuUsuario <= 0) return 0;
    var total = 0.0;
    for (final linha in linhas) {
      if (linha.promocaoId > 0) continue;
      if (linha.subtotal <= 0) continue;
      final pct = percentualEfetivo(
        produto: linha.produto,
        precoTipo: linha.precoTipo,
        tetoEmpresaOuUsuario: tetoEmpresaOuUsuario,
      );
      total += linha.subtotal * pct / 100;
    }
    return total.clamp(0, double.infinity);
  }

  /// Percentual equivalente sobre o subtotal elegivel (exibicao e entrada %).
  static double percentualEquivalenteSobreSubtotal({
    required Iterable<LinhaCalculoLimiteDescontoPdv> linhas,
    required double tetoEmpresaOuUsuario,
  }) {
    final sub = subtotalElegivel(linhas);
    if (sub <= 0.004) return 0;
    return valorMaximoDescontoReais(
          linhas: linhas,
          tetoEmpresaOuUsuario: tetoEmpresaOuUsuario,
        ) /
        sub *
        100;
  }
}

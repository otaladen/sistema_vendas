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

  /// Menor preco unitario permitido sem autorizacao de desconto acima do teto.
  static double precoMinimoUnitario({
    required double precoTabelaReferencia,
    required Produto produto,
    required String precoTipo,
    required double tetoEmpresaOuUsuario,
  }) {
    if (precoTabelaReferencia <= 0) return 0;
    final pct = percentualEfetivo(
      produto: produto,
      precoTipo: precoTipo,
      tetoEmpresaOuUsuario: tetoEmpresaOuUsuario,
    );
    return precoTabelaReferencia * (1 - pct / 100);
  }

  /// Desconto unitario (R$) acima do teto cadastrado para a tabela de preco.
  static double descontoUnitarioAcimaDoTeto({
    required double novoPrecoUnitario,
    required double precoTabelaReferencia,
    required Produto produto,
    required String precoTipo,
    required double tetoEmpresaOuUsuario,
  }) {
    if (precoTabelaReferencia <= 0 || novoPrecoUnitario >= precoTabelaReferencia) {
      return 0;
    }
    final minimo = precoMinimoUnitario(
      precoTabelaReferencia: precoTabelaReferencia,
      produto: produto,
      precoTipo: precoTipo,
      tetoEmpresaOuUsuario: tetoEmpresaOuUsuario,
    );
    if (novoPrecoUnitario >= minimo - 1e-6) return 0;
    return (minimo - novoPrecoUnitario).clamp(0, double.infinity);
  }

  /// Desconto maximo em reais na linha (preco tabela x quantidade x % teto).
  static double descontoMaximoReaisNaLinha({
    required double precoTabelaReferencia,
    required double quantidade,
    required Produto produto,
    required String precoTipo,
    required double tetoEmpresaOuUsuario,
  }) {
    if (precoTabelaReferencia <= 0 || quantidade <= 0) return 0;
    final pct = percentualEfetivo(
      produto: produto,
      precoTipo: precoTipo,
      tetoEmpresaOuUsuario: tetoEmpresaOuUsuario,
    );
    return precoTabelaReferencia * quantidade * pct / 100;
  }
}

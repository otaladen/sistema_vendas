/// Marca do item no cadastro. [Produto.fabricante] e legado e so entra se a marca estiver vazia.
abstract final class ProdutoMarca {
  ProdutoMarca._();

  static String efetiva({
    required String marca,
    String fabricante = '',
  }) {
    final m = marca.trim();
    if (m.isNotEmpty) return m;
    return fabricante.trim();
  }
}

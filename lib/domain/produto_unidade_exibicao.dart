import '../model/produto.dart';

/// Rotulo de unidade para exibicao (M2 -> M²).
String rotuloUnidadeProdutoExibicao(String unidade) {
  final u = unidade.trim().toUpperCase();
  switch (u) {
    case 'M2':
      return 'M²';
    case 'M3':
      return 'M³';
    case 'LT':
      return 'L';
    case '':
      return 'UN';
    default:
      return u;
  }
}

/// Unidade de venda (e compra, quando diferente) para listas do PDV/estoque.
String rotuloUnidadeProdutoLista(Produto produto) {
  final venda = rotuloUnidadeProdutoExibicao(produto.unidade);
  if (!produto.pdvPodeVenderEmUnidadeCompra) return venda;
  final compra = rotuloUnidadeProdutoExibicao(produto.unidadeCompraEfetiva);
  if (compra == venda) return venda;
  return '$venda · $compra';
}

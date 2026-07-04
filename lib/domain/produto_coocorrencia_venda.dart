/// Produto que costuma aparecer na mesma venda que outro (market basket).
class ProdutoCoocorrenciaVenda {
  const ProdutoCoocorrenciaVenda({
    required this.produtoId,
    required this.vendasJuntas,
    required this.quantidadeMedia,
  });

  final int produtoId;
  final int vendasJuntas;
  final double quantidadeMedia;
}

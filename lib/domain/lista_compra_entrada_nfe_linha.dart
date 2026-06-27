/// Linha de produto recebido na NF-e de entrada (para baixa na lista de compras).
class ListaCompraEntradaNfeLinha {
  const ListaCompraEntradaNfeLinha({
    required this.produtoId,
    required this.quantidadeRecebida,
    required this.fornecedorNome,
    required this.nfeChave,
  });

  final int produtoId;
  final int quantidadeRecebida;
  final String fornecedorNome;
  final String nfeChave;
}

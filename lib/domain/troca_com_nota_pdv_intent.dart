/// Parametros ao abrir o PDV apos devolucao na listagem (troca com nota fiscal).
class TrocaComNotaPdvIntent {
  const TrocaComNotaPdvIntent({
    required this.vendaOrigemId,
    required this.clienteId,
    required this.creditoDevolucaoReais,
    this.numeroVendaOrigem = 0,
    this.vendedorId,
    this.observacao,
  });

  final int vendaOrigemId;
  final int clienteId;
  final double creditoDevolucaoReais;
  final int numeroVendaOrigem;
  final int? vendedorId;
  final String? observacao;
}

/// Credito em reais pelos itens devolvidos (preco unitario da venda original).
double creditoDevolucaoReaisDeEntradas({
  required List<({int itemVendaId, int quantidade})> entradas,
  required double Function(int itemVendaId) precoUnitarioDoItem,
}) {
  var total = 0.0;
  for (final e in entradas) {
    if (e.quantidade <= 0) continue;
    total += e.quantidade * precoUnitarioDoItem(e.itemVendaId);
  }
  return total;
}

/// Credito da devolucao abatido no subtotal do PDV (nao entra no teto de desconto).
double creditoDevolucaoAplicavelNoSubtotalPdv({
  required double creditoDevolucaoReais,
  required double subtotalElegivelDesconto,
}) {
  if (creditoDevolucaoReais <= 0.004 || subtotalElegivelDesconto <= 0.004) {
    return 0;
  }
  return creditoDevolucaoReais.clamp(0.0, subtotalElegivelDesconto);
}

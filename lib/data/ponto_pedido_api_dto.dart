/// Item do GET /api/estoque/ponto-pedido (PP e badge preditivo).
class PontoPedidoApiItem {
  const PontoPedidoApiItem({
    required this.produtoId,
    required this.critico,
    required this.pontoPedido,
    required this.consumo60d,
    required this.vendaMediaDiariaExibicao,
  });

  final int produtoId;
  final bool critico;

  /// PP na unidade de venda (m² / CX / UN), nunca raw.
  final double pontoPedido;

  /// Consumo bruto do periodo (mesma escala de [ItemVenda.quantidade]).
  final int consumo60d;

  /// Media diaria ja convertida para a unidade de exibicao.
  final double vendaMediaDiariaExibicao;

  Map<String, dynamic> toApiMap() => {
        'produtoId': produtoId,
        'critico': critico,
        'pontoPedido': pontoPedido,
        'consumo60d': consumo60d,
        'vendaMediaDiariaExibicao': vendaMediaDiariaExibicao,
      };

  static PontoPedidoApiItem? fromApiMap(Map<String, dynamic> m) {
    final id = (m['produtoId'] as num?)?.toInt() ?? 0;
    if (id <= 0) return null;
    return PontoPedidoApiItem(
      produtoId: id,
      critico: m['critico'] == true,
      pontoPedido: (m['pontoPedido'] as num?)?.toDouble() ?? 0,
      consumo60d: (m['consumo60d'] as num?)?.toInt() ?? 0,
      vendaMediaDiariaExibicao:
          (m['vendaMediaDiariaExibicao'] as num?)?.toDouble() ?? 0,
    );
  }
}

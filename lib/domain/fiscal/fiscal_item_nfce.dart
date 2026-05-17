/// Item no formato esperado por APIs de NFC-e / documento fiscal.
class FiscalItemNfce {
  const FiscalItemNfce({
    required this.numeroItem,
    required this.codigoProduto,
    required this.descricao,
    required this.ncm,
    required this.cfop,
    required this.unidade,
    required this.quantidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.cest = '',
    this.grupoTributario = 'tributado',
    this.codigoBarras = '',
  });

  final int numeroItem;
  final String codigoProduto;
  final String descricao;
  final String ncm;
  final String cfop;
  final String unidade;
  final int quantidade;
  final double valorUnitario;
  final double valorTotal;
  final String cest;
  final String grupoTributario;
  final String codigoBarras;

  Map<String, dynamic> toJson() => {
        'numero_item': numeroItem,
        'codigo_produto': codigoProduto,
        'descricao': descricao,
        'ncm': ncm,
        'cfop': cfop,
        'unidade': unidade,
        'quantidade': quantidade,
        'valor_unitario': valorUnitario,
        'valor_total': valorTotal,
        if (cest.isNotEmpty) 'cest': cest,
        'grupo_tributario': grupoTributario,
        if (codigoBarras.isNotEmpty) 'codigo_barras': codigoBarras,
      };
}

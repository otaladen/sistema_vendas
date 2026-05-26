/// NF-e de entrada (compra) para fechamento contabil do mes.
class NotaFiscalEntradaFechamentoItem {
  const NotaFiscalEntradaFechamentoItem({
    required this.dataEmissao,
    required this.chaveAcesso,
    required this.cnpjFornecedor,
    required this.razaoSocialFornecedor,
    required this.numero,
    required this.serie,
    required this.valorTotal,
    required this.dataEntradaSistema,
    this.caminhoXmlLocal = '',
  });

  final DateTime dataEmissao;
  final String chaveAcesso;
  final String cnpjFornecedor;
  final String razaoSocialFornecedor;
  final String numero;
  final String serie;
  final double valorTotal;
  final DateTime dataEntradaSistema;
  final String caminhoXmlLocal;

  bool get temXmlLocal => caminhoXmlLocal.trim().isNotEmpty;

  String get nomeArquivoXml {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length >= 44) return 'NFe_entrada_$chave.xml';
    return 'NFe_entrada_${numero}_$cnpjFornecedor.xml';
  }
}

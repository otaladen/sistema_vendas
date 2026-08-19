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

  Map<String, dynamic> toJson() => {
        'dataEmissao': dataEmissao.toUtc().toIso8601String(),
        'chaveAcesso': chaveAcesso,
        'cnpjFornecedor': cnpjFornecedor,
        'razaoSocialFornecedor': razaoSocialFornecedor,
        'numero': numero,
        'serie': serie,
        'valorTotal': valorTotal,
        'dataEntradaSistema': dataEntradaSistema.toUtc().toIso8601String(),
        'caminhoXmlLocal': caminhoXmlLocal,
        'temXmlLocal': temXmlLocal,
      };

  factory NotaFiscalEntradaFechamentoItem.fromJson(Map<String, dynamic> json) {
    return NotaFiscalEntradaFechamentoItem(
      dataEmissao: DateTime.tryParse((json['dataEmissao'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      chaveAcesso: (json['chaveAcesso'] ?? '').toString(),
      cnpjFornecedor: (json['cnpjFornecedor'] ?? '').toString(),
      razaoSocialFornecedor: (json['razaoSocialFornecedor'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      valorTotal: (json['valorTotal'] as num?)?.toDouble() ?? 0,
      dataEntradaSistema:
          DateTime.tryParse((json['dataEntradaSistema'] ?? '').toString()) ??
              DateTime.now().toUtc(),
      caminhoXmlLocal: (json['caminhoXmlLocal'] ?? '').toString(),
    );
  }
}

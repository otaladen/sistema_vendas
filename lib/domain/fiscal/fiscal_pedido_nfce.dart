import 'fiscal_item_nfce.dart';

/// Pedido de emissao NFC-e (payload generico para integradores).
class FiscalPedidoNfce {
  const FiscalPedidoNfce({
    required this.referenciaInterna,
    required this.cnpjEmitente,
    required this.ufEmitente,
    required this.itens,
    this.cpfCnpjDestinatario = '',
    this.nomeDestinatario = '',
    this.valorFrete = 0,
    this.valorDesconto = 0,
    this.valorTotal,
    this.observacao = '',
    this.consumidorFinal = true,
    this.presencial = true,
  });

  final String referenciaInterna;
  final String cnpjEmitente;
  final String ufEmitente;
  final List<FiscalItemNfce> itens;
  final String cpfCnpjDestinatario;
  final String nomeDestinatario;
  final double valorFrete;
  final double valorDesconto;
  final double? valorTotal;
  final String observacao;
  final bool consumidorFinal;
  final bool presencial;

  double get totalCalculado =>
      valorTotal ??
      itens.fold<double>(0, (s, i) => s + i.valorTotal) +
          valorFrete -
          valorDesconto;

  Map<String, dynamic> toJson() => {
        'referencia_interna': referenciaInterna,
        'cnpj_emitente': cnpjEmitente,
        'uf_emitente': ufEmitente,
        'consumidor_final': consumidorFinal,
        'presencial': presencial,
        if (cpfCnpjDestinatario.isNotEmpty)
          'cpf_cnpj_destinatario': cpfCnpjDestinatario,
        if (nomeDestinatario.isNotEmpty) 'nome_destinatario': nomeDestinatario,
        'valor_frete': valorFrete,
        'valor_desconto': valorDesconto,
        'valor_total': totalCalculado,
        if (observacao.isNotEmpty) 'observacao': observacao,
        'itens': itens.map((i) => i.toJson()).toList(),
      };
}

/// Resposta padrao apos envio a API fiscal.
class FiscalEmissaoResultado {
  const FiscalEmissaoResultado({
    required this.sucesso,
    this.chaveAcesso = '',
    this.numero = '',
    this.serie = '',
    this.protocolo = '',
    this.urlDanfe = '',
    this.mensagem = '',
    this.codigoStatus = '',
    this.payloadBruto,
  });

  final bool sucesso;
  final String chaveAcesso;
  final String numero;
  final String serie;
  final String protocolo;
  final String urlDanfe;
  final String mensagem;
  final String codigoStatus;
  final Map<String, dynamic>? payloadBruto;

  factory FiscalEmissaoResultado.erro(String mensagem) =>
      FiscalEmissaoResultado(sucesso: false, mensagem: mensagem);

  factory FiscalEmissaoResultado.deJson(Map<String, dynamic> json) {
    final chave =
        (json['chave_acesso'] ?? json['chave'] ?? json['chaveAcesso'] ?? '')
            .toString()
            .trim();
    final urlDanfe = (json['url_danfe'] ??
            json['danfe'] ??
            json['url_pdf'] ??
            json['pdf_url'] ??
            json['link_danfe'] ??
            '')
        .toString()
        .trim();
    return FiscalEmissaoResultado(
      sucesso: json['sucesso'] == true ||
          json['success'] == true ||
          chave.isNotEmpty,
      chaveAcesso: chave,
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      protocolo: (json['protocolo'] ?? '').toString(),
      urlDanfe: urlDanfe,
      mensagem: (json['mensagem'] ?? json['message'] ?? '').toString(),
      codigoStatus: (json['codigo_status'] ?? json['status'] ?? '').toString(),
      payloadBruto: json,
    );
  }
}

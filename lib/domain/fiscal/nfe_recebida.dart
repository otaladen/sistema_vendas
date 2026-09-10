/// Resumo de NF-e recebida (emitida contra o CNPJ da loja) — API Focus NFe.
class NfeRecebida {
  const NfeRecebida({
    required this.chaveNfe,
    required this.nomeEmitente,
    required this.documentoEmitente,
    required this.valorTotal,
    required this.dataEmissao,
    required this.situacao,
    required this.manifestacaoDestinatario,
    this.versao = 0,
    this.nfeCompleta = false,
    this.cnpjDestinatario = '',
    this.dataCancelamento,
    this.dataCartaCorrecao,
  });

  final String chaveNfe;
  final String nomeEmitente;
  final String documentoEmitente;
  final double valorTotal;
  final DateTime? dataEmissao;
  final String situacao;
  final String manifestacaoDestinatario;
  final int versao;
  final bool nfeCompleta;
  final String cnpjDestinatario;
  final DateTime? dataCancelamento;
  final DateTime? dataCartaCorrecao;

  factory NfeRecebida.fromJson(Map<String, dynamic> json) {
    return NfeRecebida(
      chaveNfe: (json['chave_nfe'] ?? '').toString(),
      nomeEmitente: (json['nome_emitente'] ?? '').toString(),
      documentoEmitente: (json['documento_emitente'] ?? '').toString(),
      valorTotal:
          double.tryParse((json['valor_total'] ?? '0').toString()) ?? 0,
      dataEmissao: _parseDateTime(json['data_emissao']),
      situacao: (json['situacao'] ?? '').toString(),
      manifestacaoDestinatario:
          (json['manifestacao_destinatario'] ?? '').toString(),
      versao: _parseVersao(json['versao']),
      nfeCompleta: _parseBool(json['nfe_completa']),
      cnpjDestinatario: (json['cnpj_destinatario'] ?? '').toString(),
      dataCancelamento: _parseDateTime(json['data_cancelamento']),
      dataCartaCorrecao: _parseDateTime(json['data_carta_correcao']),
    );
  }

  Map<String, dynamic> toJson() => {
        'chave_nfe': chaveNfe,
        'nome_emitente': nomeEmitente,
        'documento_emitente': documentoEmitente,
        'valor_total': valorTotal.toStringAsFixed(2),
        if (dataEmissao != null) 'data_emissao': dataEmissao!.toIso8601String(),
        'situacao': situacao,
        'manifestacao_destinatario': manifestacaoDestinatario,
        'versao': versao,
        'nfe_completa': nfeCompleta,
        'cnpj_destinatario': cnpjDestinatario,
        if (dataCancelamento != null)
          'data_cancelamento': dataCancelamento!.toIso8601String(),
        if (dataCartaCorrecao != null)
          'data_carta_correcao': dataCartaCorrecao!.toIso8601String(),
      };

  NfeRecebida copyWith({
    String? chaveNfe,
    String? nomeEmitente,
    String? documentoEmitente,
    double? valorTotal,
    DateTime? dataEmissao,
    String? situacao,
    String? manifestacaoDestinatario,
    int? versao,
    bool? nfeCompleta,
    String? cnpjDestinatario,
    DateTime? dataCancelamento,
    DateTime? dataCartaCorrecao,
  }) {
    return NfeRecebida(
      chaveNfe: chaveNfe ?? this.chaveNfe,
      nomeEmitente: nomeEmitente ?? this.nomeEmitente,
      documentoEmitente: documentoEmitente ?? this.documentoEmitente,
      valorTotal: valorTotal ?? this.valorTotal,
      dataEmissao: dataEmissao ?? this.dataEmissao,
      situacao: situacao ?? this.situacao,
      manifestacaoDestinatario:
          manifestacaoDestinatario ?? this.manifestacaoDestinatario,
      versao: versao ?? this.versao,
      nfeCompleta: nfeCompleta ?? this.nfeCompleta,
      cnpjDestinatario: cnpjDestinatario ?? this.cnpjDestinatario,
      dataCancelamento: dataCancelamento ?? this.dataCancelamento,
      dataCartaCorrecao: dataCartaCorrecao ?? this.dataCartaCorrecao,
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static int _parseVersao(Object? raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static bool _parseBool(Object? raw) {
    if (raw is bool) return raw;
    final s = raw?.toString().trim().toLowerCase() ?? '';
    return s == 'true' || s == '1';
  }
}

/// Rotulos amigaveis para situacao e manifestacao (Focus / SEFAZ).
abstract final class NfeRecebidaRotulos {
  NfeRecebidaRotulos._();

  static String situacao(String codigo) {
    switch (codigo.trim().toLowerCase()) {
      case 'autorizada':
        return 'Autorizada';
      case 'cancelada':
        return 'Cancelada';
      case 'denegada':
        return 'Denegada';
      default:
        if (codigo.trim().isEmpty) return '—';
        return codigo;
    }
  }

  static String manifestacao(String codigo) {
    switch (codigo.trim().toLowerCase()) {
      case '':
      case 'nulo':
        return 'Desconhecida';
      case 'ciencia':
        return 'Ciencia da operacao';
      case 'confirmacao':
        return 'Confirmacao da operacao';
      case 'desconhecimento':
        return 'Desconhecimento';
      case 'nao_realizada':
        return 'Operacao nao realizada';
      default:
        return codigo;
    }
  }
}

/// Carta de Correcao Eletronica (CC-e) vinculada a uma NF-e de saida.
class NfeCartaCorrecaoRegistro {
  NfeCartaCorrecaoRegistro({
    required this.numeroSequencia,
    required this.textoCorrecao,
    this.urlPdf = '',
    this.urlXml = '',
    this.protocolo = '',
    this.statusFocus = 'autorizado',
    DateTime? emitidaEm,
  }) : emitidaEm = emitidaEm ?? DateTime.now();

  final int numeroSequencia;
  final String textoCorrecao;
  final String urlPdf;
  final String urlXml;
  final String protocolo;
  final String statusFocus;
  final DateTime emitidaEm;

  bool get processando =>
      statusFocus.contains('processando') && urlXml.trim().isEmpty;

  bool get autorizada =>
      urlXml.trim().isNotEmpty ||
      statusFocus == 'autorizado' ||
      protocolo.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'numeroSequencia': numeroSequencia,
        'textoCorrecao': textoCorrecao,
        if (urlPdf.trim().isNotEmpty) 'urlPdf': urlPdf,
        if (urlXml.trim().isNotEmpty) 'urlXml': urlXml,
        if (protocolo.trim().isNotEmpty) 'protocolo': protocolo,
        if (statusFocus.trim().isNotEmpty) 'statusFocus': statusFocus,
        'emitidaEm': emitidaEm.toUtc().toIso8601String(),
      };

  factory NfeCartaCorrecaoRegistro.fromJson(Map<String, dynamic> json) {
    return NfeCartaCorrecaoRegistro(
      numeroSequencia: ((json['numeroSequencia'] as num?) ?? 0).toInt(),
      textoCorrecao: (json['textoCorrecao'] ?? '').toString(),
      urlPdf: (json['urlPdf'] ?? '').toString(),
      urlXml: (json['urlXml'] ?? '').toString(),
      protocolo: (json['protocolo'] ?? '').toString(),
      statusFocus: (json['statusFocus'] ?? 'autorizado').toString(),
      emitidaEm: DateTime.tryParse((json['emitidaEm'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  NfeCartaCorrecaoRegistro copyWith({
    int? numeroSequencia,
    String? textoCorrecao,
    String? urlPdf,
    String? urlXml,
    String? protocolo,
    String? statusFocus,
    DateTime? emitidaEm,
  }) {
    return NfeCartaCorrecaoRegistro(
      numeroSequencia: numeroSequencia ?? this.numeroSequencia,
      textoCorrecao: textoCorrecao ?? this.textoCorrecao,
      urlPdf: urlPdf ?? this.urlPdf,
      urlXml: urlXml ?? this.urlXml,
      protocolo: protocolo ?? this.protocolo,
      statusFocus: statusFocus ?? this.statusFocus,
      emitidaEm: emitidaEm ?? this.emitidaEm,
    );
  }
}

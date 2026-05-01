class MensagemLog {
  const MensagemLog({
    required this.id,
    required this.clienteId,
    required this.filaId,
    required this.templateId,
    required this.canal,
    required this.destino,
    required this.requestJson,
    required this.responseJson,
    required this.resultado,
    required this.criadoEm,
    this.statusHttp = 0,
    this.statusEntrega = 'desconhecido',
    this.providerMessageId = '',
  });

  final String id;
  final int clienteId;
  final String filaId;
  final String templateId;
  final String canal;
  final String destino;
  final String requestJson;
  final String responseJson;
  final String resultado; // enviado | falhou
  final int statusHttp;
  final String statusEntrega; // enviado | entregue | lido | falhou | desconhecido
  final String providerMessageId;
  final DateTime criadoEm;

  MensagemLog copyWith({
    String? id,
    int? clienteId,
    String? filaId,
    String? templateId,
    String? canal,
    String? destino,
    String? requestJson,
    String? responseJson,
    String? resultado,
    int? statusHttp,
    String? statusEntrega,
    String? providerMessageId,
    DateTime? criadoEm,
  }) {
    return MensagemLog(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      filaId: filaId ?? this.filaId,
      templateId: templateId ?? this.templateId,
      canal: canal ?? this.canal,
      destino: destino ?? this.destino,
      requestJson: requestJson ?? this.requestJson,
      responseJson: responseJson ?? this.responseJson,
      resultado: resultado ?? this.resultado,
      statusHttp: statusHttp ?? this.statusHttp,
      statusEntrega: statusEntrega ?? this.statusEntrega,
      providerMessageId: providerMessageId ?? this.providerMessageId,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clienteId': clienteId,
      'filaId': filaId,
      'templateId': templateId,
      'canal': canal,
      'destino': destino,
      'requestJson': requestJson,
      'responseJson': responseJson,
      'resultado': resultado,
      'statusHttp': statusHttp,
      'statusEntrega': statusEntrega,
      'providerMessageId': providerMessageId,
      'criadoEm': criadoEm.toIso8601String(),
    };
  }

  factory MensagemLog.fromMap(Map<String, dynamic> map) {
    return MensagemLog(
      id: map['id'] as String? ?? '',
      clienteId: map['clienteId'] as int? ?? 0,
      filaId: map['filaId'] as String? ?? '',
      templateId: map['templateId'] as String? ?? '',
      canal: map['canal'] as String? ?? 'whatsapp',
      destino: map['destino'] as String? ?? '',
      requestJson: map['requestJson'] as String? ?? '',
      responseJson: map['responseJson'] as String? ?? '',
      resultado: map['resultado'] as String? ?? 'falhou',
      statusHttp: map['statusHttp'] as int? ?? 0,
      statusEntrega: map['statusEntrega'] as String? ?? 'desconhecido',
      providerMessageId: map['providerMessageId'] as String? ?? '',
      criadoEm:
          DateTime.tryParse(map['criadoEm'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

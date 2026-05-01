class MensagemFila {
  const MensagemFila({
    required this.id,
    required this.clienteId,
    required this.templateId,
    required this.canal,
    required this.destino,
    required this.payloadJson,
    this.status = 'pendente',
    this.tentativas = 0,
    this.erroUltimo = '',
    required this.criadaEm,
    this.enviadaEm,
    this.proximaTentativaEm,
  });

  final String id;
  final int clienteId;
  final String templateId;
  final String canal;
  final String destino;
  final String payloadJson;
  final String status; // pendente | enviando | enviado | falhou | cancelado
  final int tentativas;
  final String erroUltimo;
  final DateTime criadaEm;
  final DateTime? enviadaEm;
  final DateTime? proximaTentativaEm;

  MensagemFila copyWith({
    String? id,
    int? clienteId,
    String? templateId,
    String? canal,
    String? destino,
    String? payloadJson,
    String? status,
    int? tentativas,
    String? erroUltimo,
    DateTime? criadaEm,
    DateTime? enviadaEm,
    DateTime? proximaTentativaEm,
  }) {
    return MensagemFila(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      templateId: templateId ?? this.templateId,
      canal: canal ?? this.canal,
      destino: destino ?? this.destino,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      tentativas: tentativas ?? this.tentativas,
      erroUltimo: erroUltimo ?? this.erroUltimo,
      criadaEm: criadaEm ?? this.criadaEm,
      enviadaEm: enviadaEm ?? this.enviadaEm,
      proximaTentativaEm: proximaTentativaEm ?? this.proximaTentativaEm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clienteId': clienteId,
      'templateId': templateId,
      'canal': canal,
      'destino': destino,
      'payloadJson': payloadJson,
      'status': status,
      'tentativas': tentativas,
      'erroUltimo': erroUltimo,
      'criadaEm': criadaEm.toIso8601String(),
      'enviadaEm': enviadaEm?.toIso8601String(),
      'proximaTentativaEm': proximaTentativaEm?.toIso8601String(),
    };
  }

  factory MensagemFila.fromMap(Map<String, dynamic> map) {
    return MensagemFila(
      id: map['id'] as String? ?? '',
      clienteId: map['clienteId'] as int? ?? 0,
      templateId: map['templateId'] as String? ?? '',
      canal: map['canal'] as String? ?? 'whatsapp',
      destino: map['destino'] as String? ?? '',
      payloadJson: map['payloadJson'] as String? ?? '{}',
      status: map['status'] as String? ?? 'pendente',
      tentativas: map['tentativas'] as int? ?? 0,
      erroUltimo: map['erroUltimo'] as String? ?? '',
      criadaEm:
          DateTime.tryParse(map['criadaEm'] as String? ?? '') ?? DateTime.now(),
      enviadaEm: DateTime.tryParse(map['enviadaEm'] as String? ?? ''),
      proximaTentativaEm: DateTime.tryParse(
        map['proximaTentativaEm'] as String? ?? '',
      ),
    );
  }
}

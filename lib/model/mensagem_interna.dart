import '../domain/autorizacao_pdv_chat.dart';

/// Recado leve do mural/chat interno da loja.
class MensagemInterna {
  MensagemInterna({
    required this.id,
    required this.vendedor,
    required this.texto,
    required this.dataHora,
    this.clientId = '',
    this.pedidoNumero = 0,
    this.mencoes = const [],
    this.pendenteLocal = false,
    this.tipo = kMensagemInternaTipoTexto,
    this.payload = const {},
  });

  final int id;
  final String vendedor;
  final String texto;
  final DateTime dataHora;
  /// Idempotencia do remetente (evita duplicar no reenvio).
  final String clientId;
  final int pedidoNumero;
  final List<String> mencoes;
  /// Ainda na fila local; ainda nao confirmado no servidor.
  final bool pendenteLocal;
  /// `texto` (padrao) ou [kMensagemInternaTipoAutorizacaoPdv].
  final String tipo;
  final Map<String, dynamic> payload;

  bool get ehAutorizacaoPdv => tipo == kMensagemInternaTipoAutorizacaoPdv;

  AutorizacaoPdvChatPayload? get autorizacaoPdv {
    if (!ehAutorizacaoPdv || payload.isEmpty) return null;
    try {
      return AutorizacaoPdvChatPayload.fromMap(payload);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'vendedor': vendedor,
        'texto': texto,
        'dataHora': dataHora.toUtc().toIso8601String(),
        if (clientId.isNotEmpty) 'clientId': clientId,
        if (pedidoNumero > 0) 'pedidoNumero': pedidoNumero,
        if (mencoes.isNotEmpty) 'mencoes': mencoes,
        if (tipo.isNotEmpty && tipo != kMensagemInternaTipoTexto) 'tipo': tipo,
        if (payload.isNotEmpty) 'payload': payload,
      };

  factory MensagemInterna.fromMap(Map<String, dynamic> map) {
    final rawDt = map['dataHora'] ?? map['data_hora'];
    DateTime dt;
    if (rawDt is DateTime) {
      dt = rawDt.toUtc();
    } else {
      dt = DateTime.tryParse('$rawDt')?.toUtc() ?? DateTime.now().toUtc();
    }
    final idRaw = map['id'];
    final id = idRaw is num
        ? idRaw.toInt()
        : int.tryParse('$idRaw') ?? 0;
    final pedidoRaw = map['pedidoNumero'];
    final pedido = pedidoRaw is num
        ? pedidoRaw.toInt()
        : int.tryParse('$pedidoRaw') ?? 0;
    final mencoesRaw = map['mencoes'];
    final mencoes = <String>[];
    if (mencoesRaw is List) {
      for (final e in mencoesRaw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) mencoes.add(s);
      }
    }
    final payloadRaw = map['payload'];
    final payload = <String, dynamic>{};
    if (payloadRaw is Map) {
      payload.addAll(Map<String, dynamic>.from(payloadRaw));
    }
    final tipo = (map['tipo'] ?? kMensagemInternaTipoTexto).toString().trim();
    return MensagemInterna(
      id: id,
      vendedor: (map['vendedor'] ?? '').toString().trim(),
      texto: (map['texto'] ?? '').toString().trim(),
      dataHora: dt,
      clientId: (map['clientId'] ?? '').toString().trim(),
      pedidoNumero: pedido,
      mencoes: List<String>.unmodifiable(mencoes),
      pendenteLocal: map['pendenteLocal'] == true,
      tipo: tipo.isEmpty ? kMensagemInternaTipoTexto : tipo,
      payload: Map<String, dynamic>.unmodifiable(payload),
    );
  }

  MensagemInterna copyWith({
    int? id,
    bool? pendenteLocal,
    String? tipo,
    Map<String, dynamic>? payload,
    String? texto,
    List<String>? mencoes,
  }) {
    return MensagemInterna(
      id: id ?? this.id,
      vendedor: vendedor,
      texto: texto ?? this.texto,
      dataHora: dataHora,
      clientId: clientId,
      pedidoNumero: pedidoNumero,
      mencoes: mencoes ?? this.mencoes,
      pendenteLocal: pendenteLocal ?? this.pendenteLocal,
      tipo: tipo ?? this.tipo,
      payload: payload ?? this.payload,
    );
  }
}

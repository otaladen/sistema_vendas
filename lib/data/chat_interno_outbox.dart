import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Recado ainda nao confirmado no servidor (fila do terminal / PC).
class ChatInternoPendente {
  const ChatInternoPendente({
    required this.clientId,
    required this.vendedor,
    required this.texto,
    required this.criadoEm,
    this.tipo = '',
    this.payload = const {},
    this.mencoes = const [],
  });

  final String clientId;
  final String vendedor;
  final String texto;
  final DateTime criadoEm;
  final String tipo;
  final Map<String, dynamic> payload;
  final List<String> mencoes;

  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'vendedor': vendedor,
        'texto': texto,
        'criadoEm': criadoEm.toUtc().toIso8601String(),
        if (tipo.isNotEmpty) 'tipo': tipo,
        if (payload.isNotEmpty) 'payload': payload,
        if (mencoes.isNotEmpty) 'mencoes': mencoes,
      };

  factory ChatInternoPendente.fromMap(Map<String, dynamic> map) {
    final payloadRaw = map['payload'];
    final payload = <String, dynamic>{};
    if (payloadRaw is Map) {
      payload.addAll(Map<String, dynamic>.from(payloadRaw));
    }
    final mencoesRaw = map['mencoes'];
    final mencoes = <String>[];
    if (mencoesRaw is List) {
      for (final e in mencoesRaw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) mencoes.add(s);
      }
    }
    return ChatInternoPendente(
      clientId: (map['clientId'] ?? '').toString(),
      vendedor: (map['vendedor'] ?? '').toString(),
      texto: (map['texto'] ?? '').toString(),
      criadoEm: DateTime.tryParse('${map['criadoEm']}')?.toUtc() ??
          DateTime.now().toUtc(),
      tipo: (map['tipo'] ?? '').toString().trim(),
      payload: payload,
      mencoes: mencoes,
    );
  }
}

abstract final class ChatInternoOutbox {
  ChatInternoOutbox._();

  static const _k = 'chat_interno_outbox_v1';

  static Future<List<ChatInternoPendente>> listar() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => ChatInternoPendente.fromMap(Map<String, dynamic>.from(e)))
          .where((e) => e.clientId.isNotEmpty && e.texto.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> salvar(List<ChatInternoPendente> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _k,
      jsonEncode(items.map((e) => e.toMap()).toList()),
    );
  }
}

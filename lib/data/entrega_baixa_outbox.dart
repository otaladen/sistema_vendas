import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entrega_baixa_pendente.dart';

/// Fila persistente de baixas do motorista no terminal leve.
///
/// Celulares/terminais nao abrem o ObjectBox do ERP (so HTTP/WS). Este outbox
/// grava no aparelho e sobrevive a queda do Tailscale e a reinicio do app.
class EntregaBaixaOutbox {
  EntregaBaixaOutbox._();

  static const _kKey = 'entrega_baixa_motorista_outbox_v1';

  static Future<List<EntregaBaixaPendente>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _ler(prefs);
  }

  static Future<void> upsert(EntregaBaixaPendente item) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = EntregaBaixaFila.upsert(_ler(prefs), item);
    await _gravar(prefs, lista);
  }

  static Future<void> remover(int vendaId) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = EntregaBaixaFila.remover(_ler(prefs), vendaId);
    await _gravar(prefs, lista);
  }

  static List<EntregaBaixaPendente> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => EntregaBaixaPendente.fromMap(Map<String, dynamic>.from(m)))
          .where((e) => e.vendaId > 0)
          .where(
            (e) => e.ehNaoEntregue
                ? e.motivoCodigo.trim().isNotEmpty
                : e.recebidoPor.trim().isNotEmpty,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    List<EntregaBaixaPendente> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

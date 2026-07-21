import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Push idempotente por lote (S5) — reenvio seguro apos timeout de rede.
class SyncPushIdempotency {
  SyncPushIdempotency._();

  static const _kBatchId = 'sync_push_pending_batch_id_v1';
  static const _kMutations = 'sync_push_pending_mutations_v1';

  static String gerarBatchId(String deviceId) {
    final rnd = Random.secure();
    final salt = List.generate(6, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${deviceId.trim()}-${DateTime.now().toUtc().millisecondsSinceEpoch}-$salt';
  }

  static Future<({String batchId, List<Map<String, dynamic>> mutations})?>
      carregarPendente() async {
    final prefs = await SharedPreferences.getInstance();
    final batchId = prefs.getString(_kBatchId)?.trim() ?? '';
    final raw = prefs.getString(_kMutations);
    if (batchId.isEmpty || raw == null || raw.trim().isEmpty) return null;
    try {
      final mutations = await Isolate.run(() {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return <Map<String, dynamic>>[];
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      });
      if (mutations.isEmpty) return null;
      return (batchId: batchId, mutations: mutations);
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvarPendente({
    required String batchId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    if (batchId.trim().isEmpty || mutations.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBatchId, batchId.trim());
    final encoded = await Isolate.run(() => jsonEncode(mutations));
    await prefs.setString(_kMutations, encoded);
  }

  static Future<void> limparPendente() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBatchId);
    await prefs.remove(_kMutations);
  }
}

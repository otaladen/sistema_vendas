import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Deletes locais pendentes de envio na sync LAN (S2).
class SyncDeleteOutbox {
  SyncDeleteOutbox._();

  static const _kKey = 'sync_delete_outbox_v1';

  static Future<void> registrar({
    required String entity,
    required int entityId,
    int? localId,
  }) async {
    if (entity.trim().isEmpty || entityId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _lerLista(prefs);
    final chave = '${entity.trim()}:$entityId';
    if (lista.any((e) => e.chave == chave)) return;
    lista.add(
      _SyncDeleteEntry(
        entity: entity.trim(),
        entityId: entityId,
        localId: localId ?? entityId,
      ),
    );
    await _gravarLista(prefs, lista);
  }

  static Future<List<Map<String, dynamic>>> mutacoesParaPush() async {
    final lista = await _listar();
    return lista
        .map(
          (e) => {
            'entity': e.entity,
            'op': 'delete',
            'entityId': e.entityId,
            'localId': e.localId,
          },
        )
        .toList();
  }

  static Future<void> limparEnviadas(
    Iterable<Map<String, dynamic>> mutacoes,
  ) async {
    final deletes = mutacoes
        .where((m) => (m['op'] ?? '').toString() == 'delete')
        .map(
          (m) => _SyncDeleteEntry(
            entity: (m['entity'] ?? '').toString(),
            entityId: (m['entityId'] as num?)?.toInt() ?? 0,
            localId: (m['localId'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((e) => e.entity.isNotEmpty && e.entityId > 0)
        .toList();
    if (deletes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lista = _lerLista(prefs);
    final remover = deletes.map((e) => e.chave).toSet();
    lista.removeWhere((e) => remover.contains(e.chave));
    await _gravarLista(prefs, lista);
  }

  static Future<List<_SyncDeleteEntry>> _listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _lerLista(prefs);
  }

  static List<_SyncDeleteEntry> _lerLista(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => _SyncDeleteEntry.fromMap(Map<String, dynamic>.from(m)))
          .where((e) => e.entity.isNotEmpty && e.entityId > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravarLista(
    SharedPreferences prefs,
    List<_SyncDeleteEntry> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

class _SyncDeleteEntry {
  const _SyncDeleteEntry({
    required this.entity,
    required this.entityId,
    required this.localId,
  });

  final String entity;
  final int entityId;
  final int localId;

  String get chave => '$entity:$entityId';

  Map<String, dynamic> toMap() => {
        'entity': entity,
        'entityId': entityId,
        'localId': localId,
      };

  factory _SyncDeleteEntry.fromMap(Map<String, dynamic> m) {
    return _SyncDeleteEntry(
      entity: (m['entity'] ?? '').toString(),
      entityId: (m['entityId'] as num?)?.toInt() ?? 0,
      localId: (m['localId'] as num?)?.toInt() ?? 0,
    );
  }
}

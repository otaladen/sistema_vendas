import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Entidades alteradas localmente aguardando push delta (S4).
class SyncDirtyOutbox {
  SyncDirtyOutbox._();

  static const _kKey = 'sync_dirty_outbox_v1';
  static const _kBootstrap = 'sync_dirty_bootstrap_v1';

  /// [entityId] == 0 = reenviar todas as linhas da entidade no proximo push.
  static Future<void> registrar({
    required String entity,
    required int entityId,
  }) async {
    final ent = entity.trim();
    if (ent.isEmpty || entityId < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _lerLista(prefs);
    final chave = _chave(ent, entityId);
    lista.removeWhere((e) => e.chave == chave);
    lista.add(_SyncDirtyEntry(entity: ent, entityId: entityId));
    await _gravarLista(prefs, lista);
  }

  static Future<void> remover({
    required String entity,
    required int entityId,
  }) async {
    final ent = entity.trim();
    if (ent.isEmpty || entityId <= 0) return;
    await removerVarios(entity: ent, entityIds: [entityId]);
  }

  /// Remove marcações dirty de varios IDs (ou de toda a entidade se [entityIds] vazio).
  static Future<void> removerVarios({
    required String entity,
    Iterable<int> entityIds = const [],
  }) async {
    final ent = entity.trim();
    if (ent.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _lerLista(prefs);
    final antes = lista.length;
    final ids = entityIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) {
      lista.removeWhere((e) => e.entity == ent);
    } else {
      final chaves = ids.map((id) => _chave(ent, id)).toSet();
      lista.removeWhere((e) => chaves.contains(e.chave));
    }
    if (lista.length != antes) await _gravarLista(prefs, lista);
  }

  static Future<List<SyncDirtyPendingEntry>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _lerLista(prefs);
  }

  static Future<bool> precisaBootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kBootstrap) ?? false);
  }

  static Future<void> marcarBootstrapConcluido() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBootstrap, true);
  }

  static Future<void> limparEnviadas(
    Iterable<Map<String, dynamic>> mutacoes,
  ) async {
    final upserts = mutacoes
        .where((m) => (m['op'] ?? 'upsert').toString() == 'upsert')
        .map(
          (m) => _SyncDirtyEntry(
            entity: (m['entity'] ?? '').toString(),
            entityId: (m['localId'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((e) => e.entity.isNotEmpty && e.entityId > 0)
        .toList();
    final entidadesEnviadas = mutacoes
        .where((m) => (m['op'] ?? 'upsert').toString() == 'upsert')
        .map((m) => (m['entity'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (upserts.isEmpty && entidadesEnviadas.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lista = _lerLista(prefs);
    final remover = upserts.map((e) => e.chave).toSet();
    lista.removeWhere(
      (e) =>
          remover.contains(e.chave) ||
          (e.sincronizarTodas && entidadesEnviadas.contains(e.entity)),
    );
    await _gravarLista(prefs, lista);
  }

  static Future<void> limparTudo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  static String _chave(String entity, int entityId) => '$entity:$entityId';

  static List<_SyncDirtyEntry> _lerLista(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => _SyncDirtyEntry.fromMap(Map<String, dynamic>.from(m)))
          .where((e) => e.entity.isNotEmpty && e.entityId >= 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravarLista(
    SharedPreferences prefs,
    List<_SyncDirtyEntry> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

class SyncDirtyPendingEntry {
  const SyncDirtyPendingEntry({
    required this.entity,
    required this.entityId,
  });

  final String entity;
  final int entityId;

  String get chave => SyncDirtyOutbox._chave(entity, entityId);

  bool get sincronizarTodas => entityId == 0;

  Map<String, dynamic> toMap() => {
        'entity': entity,
        'entityId': entityId,
      };

  factory SyncDirtyPendingEntry.fromMap(Map<String, dynamic> m) {
    return SyncDirtyPendingEntry(
      entity: (m['entity'] ?? '').toString(),
      entityId: (m['entityId'] as num?)?.toInt() ?? 0,
    );
  }
}

class _SyncDirtyEntry extends SyncDirtyPendingEntry {
  const _SyncDirtyEntry({
    required super.entity,
    required super.entityId,
  });

  factory _SyncDirtyEntry.fromMap(Map<String, dynamic> m) {
    return _SyncDirtyEntry(
      entity: (m['entity'] ?? '').toString(),
      entityId: (m['entityId'] as num?)?.toInt() ?? 0,
    );
  }
}

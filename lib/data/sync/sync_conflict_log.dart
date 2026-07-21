import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncConflictTipo {
  editEdit,
  estoqueMerge,
  timestampSkip,
  configMerge,
}

class SyncConflictEntry {
  SyncConflictEntry({
    required this.tipo,
    required this.entity,
    required this.entityId,
    required this.detalhe,
    required this.em,
  });

  final SyncConflictTipo tipo;
  final String entity;
  final int entityId;
  final String detalhe;
  final DateTime em;

  String get rotuloTipo {
    switch (tipo) {
      case SyncConflictTipo.editEdit:
        return 'Edicao simultanea';
      case SyncConflictTipo.estoqueMerge:
        return 'Estoque preservado local';
      case SyncConflictTipo.timestampSkip:
        return 'Alteracao remota ignorada';
      case SyncConflictTipo.configMerge:
        return 'Config mesclada';
    }
  }

  Map<String, dynamic> toMap() => {
        'tipo': tipo.name,
        'entity': entity,
        'entityId': entityId,
        'detalhe': detalhe,
        'em': em.toUtc().millisecondsSinceEpoch,
      };

  factory SyncConflictEntry.fromMap(Map<String, dynamic> m) {
    final tipoRaw = (m['tipo'] ?? '').toString();
    final tipo = SyncConflictTipo.values.firstWhere(
      (t) => t.name == tipoRaw,
      orElse: () => SyncConflictTipo.editEdit,
    );
    return SyncConflictEntry(
      tipo: tipo,
      entity: (m['entity'] ?? '').toString(),
      entityId: (m['entityId'] as num?)?.toInt() ?? 0,
      detalhe: (m['detalhe'] ?? '').toString(),
      em: DateTime.fromMillisecondsSinceEpoch(
        (m['em'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }
}

/// Log local de conflitos / mesclas na sync (S6).
class SyncConflictLog {
  SyncConflictLog._();

  static const _kKey = 'sync_conflict_log_v1';
  static const _max = 40;

  static final ValueNotifier<List<SyncConflictEntry>> recentes =
      ValueNotifier<List<SyncConflictEntry>>(const []);

  static bool _carregado = false;

  static Future<void> registrar({
    required SyncConflictTipo tipo,
    required String entity,
    required int entityId,
    required String detalhe,
  }) async {
    final entry = SyncConflictEntry(
      tipo: tipo,
      entity: entity.trim(),
      entityId: entityId,
      detalhe: detalhe.trim(),
      em: DateTime.now().toUtc(),
    );
    if (entry.entity.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    lista.insert(0, entry);
    while (lista.length > _max) {
      lista.removeLast();
    }
    await _gravar(prefs, lista);
    recentes.value = List.unmodifiable(lista);
  }

  static Future<void> carregarSeNecessario() async {
    if (_carregado) return;
    final prefs = await SharedPreferences.getInstance();
    var lista = _ler(prefs);
    // Avisos de "edicao simultanea" / config mesclada nao pedem mais acao:
    // o remoto ja e aplicado automaticamente na rede.
    final filtrada = lista
        .where(
          (e) =>
              e.tipo != SyncConflictTipo.editEdit &&
              e.tipo != SyncConflictTipo.configMerge,
        )
        .toList();
    if (filtrada.length != lista.length) {
      await _gravar(prefs, filtrada);
      lista = filtrada;
    }
    recentes.value = List.unmodifiable(lista);
    _carregado = true;
  }

  /// Remove avisos antigos que exigiam "Aceitar remoto" (agora automatico).
  static Future<void> limparAvisosDeAceiteRemoto() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    final filtrada = lista
        .where(
          (e) =>
              e.tipo != SyncConflictTipo.editEdit &&
              e.tipo != SyncConflictTipo.configMerge,
        )
        .toList();
    if (filtrada.length == lista.length) {
      recentes.value = List.unmodifiable(lista);
      return;
    }
    await _gravar(prefs, filtrada);
    recentes.value = List.unmodifiable(filtrada);
    _carregado = true;
  }

  static Future<void> remover(SyncConflictEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    lista.removeWhere(
      (e) =>
          e.entity == entry.entity &&
          e.entityId == entry.entityId &&
          e.em.toUtc().millisecondsSinceEpoch ==
              entry.em.toUtc().millisecondsSinceEpoch,
    );
    await _gravar(prefs, lista);
    recentes.value = List.unmodifiable(lista);
  }

  static List<SyncConflictEntry> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => SyncConflictEntry.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    List<SyncConflictEntry> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

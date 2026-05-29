import 'lan_sync_scheduler.dart';
import 'sync_conflict_log.dart';
import 'sync_dirty_outbox.dart';

/// Acoes do operador sobre conflitos registrados na sync (S6+).
class SyncConflictResolver {
  SyncConflictResolver._();

  /// Remoto ja foi aplicado; descarta dirty local pendente.
  static Future<void> aceitarRemoto(SyncConflictEntry entry) async {
    final id = entry.entityId <= 0 && entry.entity != 'empresa_config'
        ? 0
        : (entry.entity == 'empresa_config' ? 1 : entry.entityId);
    if (id > 0 || entry.entity == 'empresa_config') {
      await SyncDirtyOutbox.remover(entity: entry.entity, entityId: id);
    }
    await SyncConflictLog.remover(entry);
  }

  /// Reenvia versao local na proxima sync.
  static Future<void> manterLocal(SyncConflictEntry entry) async {
    final id = entry.entity == 'empresa_config'
        ? 1
        : (entry.entityId <= 0 ? 0 : entry.entityId);
    await SyncDirtyOutbox.registrar(entity: entry.entity, entityId: id);
    await SyncConflictLog.remover(entry);
    await LanSyncScheduler.solicitarSyncImediato();
  }

  static Future<void> dispensar(SyncConflictEntry entry) async {
    await SyncConflictLog.remover(entry);
  }
}

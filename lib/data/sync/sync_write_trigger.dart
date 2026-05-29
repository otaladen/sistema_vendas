import 'dart:async';

import 'lan_sync_scheduler.dart';
import 'sync_delete_outbox.dart';
import 'sync_dirty_outbox.dart';

bool _silenciarNotificacaoRede = false;

/// Evita loop de sync ao aplicar alteracoes vindas do servidor (pull).
void enterSyncApplySilencioso() {
  _silenciarNotificacaoRede = true;
}

void leaveSyncApplySilencioso() {
  _silenciarNotificacaoRede = false;
}

/// Chamado pelos repositorios apos gravacao bem-sucedida para propagar na LAN.
///
/// Com [entidade]/[entidadeId], registra delta no outbox (S4).
/// [entidadeId] == 0 marca todas as linhas da entidade no proximo push.
void notificarAlteracaoParaRede({String? entidade, int? entidadeId}) {
  if (_silenciarNotificacaoRede) return;
  if (entidade != null &&
      entidade.trim().isNotEmpty &&
      entidadeId != null &&
      entidadeId >= 0) {
    unawaited(
      SyncDirtyOutbox.registrar(
        entity: entidade.trim(),
        entityId: entidadeId,
      ),
    );
  }
  unawaited(LanSyncScheduler.solicitarSyncImediato());
}

/// Registra delete local para envio `{ op: delete }` na proxima sync.
void registrarDeleteParaRede(
  String entity,
  int entityId, {
  int? localId,
}) {
  if (_silenciarNotificacaoRede) return;
  unawaited(
    SyncDeleteOutbox.registrar(
      entity: entity,
      entityId: entityId,
      localId: localId,
    ),
  );
  unawaited(
    SyncDirtyOutbox.remover(entity: entity, entityId: entityId),
  );
  notificarAlteracaoParaRede();
}

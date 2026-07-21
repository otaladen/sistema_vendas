import 'dart:async';

import 'lan_sync_scheduler.dart';
import 'sync_delete_outbox.dart';
import 'sync_dirty_outbox.dart';
import 'sync_priority.dart';

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
///
/// Prioridade:
/// - alta (venda/estoque): push quase imediato
/// - media (cadastros/entregas): debounce curto
/// - baixa (config fria): so marca dirty; sobe no timer ou pull-to-refresh
///
/// O registro no dirty e aguardado antes de agendar o sync (evita corrida de
/// 350ms em que o push saia vazio e o orcamento nunca suba).
void notificarAlteracaoParaRede({String? entidade, int? entidadeId}) {
  if (_silenciarNotificacaoRede) return;
  unawaited(
    _notificarAlteracaoParaRedeAsync(
      entidade: entidade,
      entidadeId: entidadeId,
    ),
  );
}

Future<void> _notificarAlteracaoParaRedeAsync({
  String? entidade,
  int? entidadeId,
}) async {
  if (entidade != null &&
      entidade.trim().isNotEmpty &&
      entidadeId != null &&
      entidadeId >= 0) {
    await SyncDirtyOutbox.registrar(
      entity: entidade.trim(),
      entityId: entidadeId,
    );
  }

  final prioridade = SyncPriorityCatalogo.de(entidade);
  switch (prioridade) {
    case SyncPrioridade.alta:
      await LanSyncScheduler.solicitarSyncPrioritario();
    case SyncPrioridade.media:
      await LanSyncScheduler.solicitarSyncImediato();
    case SyncPrioridade.baixa:
      // Passivo: dirty fica no outbox ate timer periodico ou sync manual.
      break;
  }
}

/// Registra delete local para envio `{ op: delete }` na proxima sync.
void registrarDeleteParaRede(
  String entity,
  int entityId, {
  int? localId,
}) {
  if (_silenciarNotificacaoRede) return;
  unawaited(
    _registrarDeleteParaRedeAsync(entity, entityId, localId: localId),
  );
}

Future<void> _registrarDeleteParaRedeAsync(
  String entity,
  int entityId, {
  int? localId,
}) async {
  await SyncDeleteOutbox.registrar(
    entity: entity,
    entityId: entityId,
    localId: localId,
  );
  await SyncDirtyOutbox.remover(entity: entity, entityId: entityId);
  // Delete segue a prioridade da entidade (alta/media dispara; baixa espera).
  await _notificarAlteracaoParaRedeAsync(
    entidade: entity,
    entidadeId: entityId,
  );
}

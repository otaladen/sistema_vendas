import 'dart:async';

import 'lan_sync_scheduler.dart';

bool _silenciarNotificacaoRede = false;

/// Evita loop de sync ao aplicar alteracoes vindas do servidor (pull).
void enterSyncApplySilencioso() {
  _silenciarNotificacaoRede = true;
}

void leaveSyncApplySilencioso() {
  _silenciarNotificacaoRede = false;
}

/// Chamado pelos repositorios apos gravacao bem-sucedida para propagar na LAN o mais rapido possivel.
void notificarAlteracaoParaRede() {
  if (_silenciarNotificacaoRede) return;
  unawaited(LanSyncScheduler.solicitarSyncImediato());
}

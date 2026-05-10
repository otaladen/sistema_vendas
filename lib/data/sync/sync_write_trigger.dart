import 'dart:async';

import 'lan_sync_scheduler.dart';

/// Chamado pelos repositorios apos gravacao bem-sucedida para propagar na LAN o mais rapido possivel.
void notificarAlteracaoParaRede() {
  unawaited(LanSyncScheduler.solicitarSyncImediato());
}

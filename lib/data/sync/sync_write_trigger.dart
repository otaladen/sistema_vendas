import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/lan_api_server.dart';
import 'caixa_local_refresh_hub.dart';
import 'entrega_local_refresh_hub.dart';
import 'estoque_local_refresh_hub.dart';
import 'lan_sync_scheduler.dart';
import 'sync_delete_outbox.dart';
import 'sync_dirty_outbox.dart';
import 'sync_priority.dart';
import 'sync_refresh_hub.dart';

bool _silenciarNotificacaoRede = false;

/// Evita loop de sync ao aplicar alteracoes vindas do servidor (pull).
void enterSyncApplySilencioso() {
  _silenciarNotificacaoRede = true;
}

void leaveSyncApplySilencioso() {
  _silenciarNotificacaoRede = false;
}

/// PC Windows com LanApi ativa: propaga via WebSocket aos terminais, sem outbox P2P.
bool _propagarViaLanApiServidor() {
  if (kIsWeb) return false;
  try {
    if (!Platform.isWindows) return false;
  } catch (_) {
    return false;
  }
  return LanApiServerHub.instance.ativo;
}

/// Chamado pelos repositorios apos gravacao bem-sucedida para propagar na LAN.
///
/// No PC servidor Windows (LanApi 8788 ativa): notifica terminais via WS.
/// No celular em modo antigo: marca dirty outbox e agenda pull/push.
///
/// Com [entidade]/[entidadeId], registra delta no outbox (S4) — so clientes.
/// [entidadeId] == 0 marca todas as linhas da entidade no proximo push.
void notificarAlteracaoParaRede({
  String? entidade,
  int? entidadeId,
  List<int>? entidadeIds,
}) {
  if (_silenciarNotificacaoRede) return;

  if (_propagarViaLanApiServidor()) {
    final e = entidade?.trim();
    if (e != null && e.isNotEmpty) {
      final ids = entidadeIds ??
          (entidadeId != null && entidadeId > 0 ? <int>[entidadeId] : null);
      LanApiServerHub.instance.notificar(e, ids: ids);
      // PC1 UI: LanApiDeps usa outra instancia de ProdutoRepository; forca
      // a shell a re-ler o ObjectBox compartilhado sem esperar timer.
      if (e == 'produto') {
        EstoqueLocalRefreshHub.instance.notificar(ids: ids);
      }
      if (e == 'nfe_importada') {
        SyncRefreshHub.instance.notificarDadosAtualizados();
      }
      if (e == 'recado_loja') {
        // PC1: UI do Inicio / Recados escuta SyncRefreshHub (API so manda WS).
        SyncRefreshHub.instance.notificarDadosAtualizados();
      }
      if (e == 'inventario') {
        SyncRefreshHub.instance.notificarDadosAtualizados();
      }
      if (e == 'venda' || e == 'titulo_receber' || e == 'recebimento_fiado') {
        // KPI "Vendas hoje" / financeiro no Inicio do PC servidor.
        SyncRefreshHub.instance.notificarDadosAtualizados();
      }
      if (e == 'caixa_sessoes' || e == 'caixa') {
        CaixaLocalRefreshHub.instance.notificar();
      }
      if (e == 'venda' ||
          e == 'entrega' ||
          e == 'conferencia_carga' ||
          e == 'conferencia_carga_romaneio') {
        EntregaLocalRefreshHub.instance.notificar();
      }
    }
    return;
  }

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

  if (_propagarViaLanApiServidor()) {
    final e = entity.trim();
    if (e.isNotEmpty) {
      LanApiServerHub.instance.notificar(e);
    }
    return;
  }

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

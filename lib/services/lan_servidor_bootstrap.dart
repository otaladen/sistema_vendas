import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_config_repository.dart';
import '../data/api/lan_api_url.dart';
import '../data/objectbox.dart';
import '../data/sync/estoque_local_refresh_hub.dart';
import 'entrega_pod_retencao_service.dart';
import 'lan_api_server.dart';
import 'lan_api/lan_api_deps.dart';
import 'lan_rede_helper.dart';
import 'windows_app_startup_helper.dart';

/// Sobe a API de terminais Windows (8788) **antes do login**.
///
/// No PC1 servidor Windows: esta e a unica forma de expor dados na LAN.
/// Celular e terminal usam a mesma API. Nao inicia SyncService.
abstract final class LanServidorBootstrap {
  LanServidorBootstrap._();

  static bool _emAndamento = false;
  static bool _ok = false;
  static String? ultimoErro;
  static DateTime? iniciadoEm;
  static VoidCallback? _listenerEstoqueLanApi;

  static bool get ativo => _ok && LanApiServerHub.instance.ativo;

  static Future<void> garantirAtivo({
    required ObjectBox objectBox,
    required AppConfigRepository configRepository,
  }) async {
    if (kIsWeb || !Platform.isWindows) return;
    if (_emAndamento) return;

    _emAndamento = true;
    ultimoErro = null;
    try {
      final config = await configRepository.carregarEmpresaConfig();
      if (!config.redeSincronizacaoAtiva || !config.redeModoServidor) {
        return;
      }

      // PC servidor: garante subir com o Windows (terminais sem abrir a UI).
      await WindowsAppStartupHelper.garantirRegistroSeServidor();

      final deps = LanApiDeps.fromObjectBox(
        objectBox,
        syncToken: config.redeSyncToken,
        notificar: (e, {List<int>? ids}) =>
            LanApiServerHub.instance.notificar(e, ids: ids),
        notificarEvento: (type, payload) =>
            LanApiServerHub.instance.notificarEvento(type, payload),
      );

      // LanApi usa outra instancia de ProdutoRepository: invalida cache de busca
      // quando o estoque/cadastro muda no ObjectBox compartilhado.
      if (_listenerEstoqueLanApi != null) {
        EstoqueLocalRefreshHub.instance.removeListener(_listenerEstoqueLanApi!);
      }
      _listenerEstoqueLanApi = () {
        try {
          deps.produtoRepository.invalidarCacheBusca();
        } catch (_) {}
      };
      EstoqueLocalRefreshHub.instance.addListener(_listenerEstoqueLanApi!);

      await LanRedeHelper.encerrarHubLegadoSeExistir();

      // Sempre recria a API neste processo para carregar rotas novas
      // (ex.: /api/auth/login) e liberar instancia zumbi na 8788.
      if (LanApiServerHub.instance.ativo) {
        await LanApiServerHub.instance.parar();
      }

      final api = LanApiServer(
        objectBox: objectBox,
        produtoRepository: deps.produtoRepository,
        clienteRepository: deps.clienteRepository,
        vendaRepository: deps.vendaRepository,
        vendedorRepository: deps.vendedorRepository,
        syncToken: config.redeSyncToken,
        deps: deps,
      );
      await LanApiServerHub.instance.iniciar(
        api,
        porta: LanApiUrl.portaPadrao,
      );

      _ok = LanApiServerHub.instance.ativo;
      if (_ok) {
        iniciadoEm = DateTime.now();
        debugPrint(
          'LanServidorBootstrap: API ERP completa na porta '
          '${LanApiUrl.portaPadrao}.',
        );
        unawaited(
          EntregaPodRetencaoService.aplicarSeConfigurado(configRepository),
        );
      } else {
        ultimoErro =
            'API de terminais nao iniciou (porta ${LanApiUrl.portaPadrao}).';
      }
    } catch (e, st) {
      ultimoErro = '$e';
      debugPrint('LanServidorBootstrap falhou: $e\n$st');
    } finally {
      _emAndamento = false;
    }
  }

  static Future<void> reiniciar({
    required ObjectBox objectBox,
    required AppConfigRepository configRepository,
  }) async {
    _ok = false;
    await LanApiServerHub.instance.parar();
    await garantirAtivo(
      objectBox: objectBox,
      configRepository: configRepository,
    );
  }
}

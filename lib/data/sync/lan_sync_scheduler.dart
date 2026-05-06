import 'dart:async';

import '../app_config_repository.dart';
import 'sync_service.dart';

/// Agenda sincronizacao periodica quando a rede esta habilitada nas configuracoes.
class LanSyncScheduler {
  LanSyncScheduler({
    required SyncService syncService,
    AppConfigRepository? configRepository,
    this.intervalo = const Duration(minutes: 2),
  })  : _syncService = syncService,
        _configRepository = configRepository ?? AppConfigRepository();

  final SyncService _syncService;
  final AppConfigRepository _configRepository;
  final Duration intervalo;

  Timer? _timer;
  bool _rodando = false;

  bool get estaAgendado => _timer != null;

  /// Inicia timer + uma sincronizacao imediata se [redeSincronizacaoAtiva].
  Future<void> iniciar() async {
    await parar();
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva ||
        config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    await sincronizarAgora();
    _timer = Timer.periodic(intervalo, (_) => sincronizarAgora());
  }

  Future<void> parar() async {
    _timer?.cancel();
    _timer = null;
  }

  /// Uma execucao (usada pelo timer e pelo botao em Configuracoes).
  Future<String?> sincronizarAgora() async {
    if (_rodando) return null;
    _rodando = true;
    try {
      return await _syncService.executarSync();
    } finally {
      _rodando = false;
    }
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_config_repository.dart';
import 'sync_api_client.dart';
import 'sync_cursor_storage.dart';
import 'sync_service.dart';

/// Agenda sincronizacao periodica quando a rede esta habilitada nas configuracoes.
///
/// Mantem tambem WebSocket `/sync/stream` para disparar [sincronizarAgora] assim que
/// outro PC gravar no servidor (tempo real na LAN).
class LanSyncScheduler {
  LanSyncScheduler({
    required SyncService syncService,
    AppConfigRepository? configRepository,
    this.intervalo = const Duration(seconds: 30),
  })  : _syncService = syncService,
        _configRepository = configRepository ?? AppConfigRepository();

  final SyncService _syncService;
  final AppConfigRepository _configRepository;
  final Duration intervalo;

  Timer? _timer;
  Timer? _heartbeatTimer;
  final SyncCursorStorage _cursorStorage = SyncCursorStorage();

  /// Garante que varias chamadas a [sincronizarAgora] (timer + WS + repositorios) rodem em serie.
  Future<void> _mutexSync = Future<void>.value();

  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSub;
  Timer? _reconnectRealtimeTimer;
  Timer? _debounceSyncEvento;

  /// Ultimo scheduler ligado pelo menu principal (logout chama [parar]).
  static LanSyncScheduler? _instanciaAtiva;

  bool get estaAgendado => _timer != null;

  /// Inicia timer + uma sincronizacao imediata se [redeSincronizacaoAtiva].
  Future<void> iniciar() async {
    await parar();
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva ||
        config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    _instanciaAtiva = this;
    await sincronizarAgora();
    _timer = Timer.periodic(intervalo, (_) => sincronizarAgora());
    unawaited(_conectarTempoReal());
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => unawaited(_enviarHeartbeat()));
    unawaited(_enviarHeartbeat());
  }

  String _rotuloEstacaoParaHeartbeat() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isWindows) {
        final n = Platform.environment['COMPUTERNAME'];
        if (n != null && n.trim().isNotEmpty) return n.trim();
      }
      return Platform.localHostname.trim();
    } catch (_) {
      return 'app';
    }
  }

  Future<void> _enviarHeartbeat() async {
    if (_instanciaAtiva != this) return;
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva || config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    final client = SyncApiClient(baseUrl: config.redeServidorUrl);
    if (!client.configurado) return;
    try {
      final stationId = await _cursorStorage.obterOuCriarDeviceId();
      await client.heartbeat(
        stationId: stationId,
        label: _rotuloEstacaoParaHeartbeat(),
      );
    } catch (_) {}
  }

  Future<void> parar() async {
    if (_instanciaAtiva == this) {
      _instanciaAtiva = null;
    }
    _timer?.cancel();
    _timer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectRealtimeTimer?.cancel();
    _reconnectRealtimeTimer = null;
    _debounceSyncEvento?.cancel();
    _debounceSyncEvento = null;
    _mutexSync = Future<void>.value();
    await _realtimeSub?.cancel();
    _realtimeSub = null;
    await _realtimeChannel?.sink.close();
    _realtimeChannel = null;
  }

  Future<void> _fecharSomenteCanalWs() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;
    await _realtimeChannel?.sink.close();
    _realtimeChannel = null;
  }

  Uri? _uriWebSocketDaBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) {
      s = 'http://$s';
    }
    final u = Uri.parse(s);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/sync/stream',
    );
  }

  Future<void> _conectarTempoReal() async {
    await _fecharSomenteCanalWs();
    if (_instanciaAtiva != this) return;
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva ||
        config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    final wsUri = _uriWebSocketDaBase(config.redeServidorUrl.trim());
    if (wsUri == null) return;
    try {
      _realtimeChannel = WebSocketChannel.connect(wsUri);
      _realtimeSub = _realtimeChannel!.stream.listen(
        (_) => _aoReceberEventoTempoReal(),
        onError: (_) => _agendarReconectarTempoReal(),
        onDone: _agendarReconectarTempoReal,
      );
    } catch (_) {
      _agendarReconectarTempoReal();
    }
  }

  void _agendarReconectarTempoReal() {
    if (_instanciaAtiva != this) return;
    _reconnectRealtimeTimer?.cancel();
    _reconnectRealtimeTimer = Timer(const Duration(seconds: 5), () {
      if (_instanciaAtiva == this) {
        unawaited(_conectarTempoReal());
      }
    });
  }

  void _aoReceberEventoTempoReal() {
    _debounceSyncEvento?.cancel();
    _debounceSyncEvento = Timer(const Duration(milliseconds: 100), () {
      unawaited(sincronizarAgora());
    });
  }

  /// Apos gravacao local (orcamento, venda, etc.) para enviar/receber dados sem esperar o timer.
  static Future<void> solicitarSyncImediato() async {
    await _instanciaAtiva?.sincronizarAgora();
  }

  /// Uma execucao (usada pelo timer e pelo botao em Configuracoes).
  Future<String?> sincronizarAgora() async {
    final anterior = _mutexSync;
    final liberado = Completer<void>();
    _mutexSync = liberado.future;
    await anterior;
    try {
      return await _syncService.executarSync();
    } finally {
      liberado.complete();
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_config_repository.dart';
import 'sync_api_client.dart';
import 'sync_cursor_storage.dart';
import 'sync_implantacao_config.dart';
import 'sync_presence_hub.dart';
import 'sync_priority.dart';
import 'sync_service.dart';
import 'sync_auth.dart';

/// Agenda sincronizacao periodica quando a rede esta habilitada nas configuracoes.
///
/// Mantem tambem WebSocket `/sync/stream` para disparar sync quando a revision
/// remota for maior que a local (evita pull pesado em vao).
class LanSyncScheduler {
  LanSyncScheduler({
    required SyncService syncService,
    AppConfigRepository? configRepository,
    this.intervalo = const Duration(seconds: 90),
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
  int _reconnectTentativa = 0;
  int _debounceRedeGeracao = 0;

  /// Revision remota recebida durante grace do celular (flush ao sair do grace).
  int? _revisionPendenteGrace;

  /// Debounce compartilhado para escritas locais (media / alta).
  static Timer? _debounceSyncEscrita;
  static Timer? _debounceSyncPrioritario;

  /// Ultimo scheduler ligado pelo menu principal (logout chama [parar]).
  static LanSyncScheduler? _instanciaAtiva;

  /// No celular: bloqueia sync automatico nos primeiros segundos apos entrar.
  DateTime? _graceAte;

  bool get estaAgendado => _timer != null;

  static bool get _plataformaCelular =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Janela em que o celular nao faz sync automatico (timer/1o pull).
  /// Escritas locais de alta prioridade sincronizam mesmo assim.
  static const Duration _graceCelular = Duration(seconds: 20);

  bool get _emGraceCelular {
    if (!_plataformaCelular) return false;
    final ate = _graceAte;
    if (ate == null) return false;
    return DateTime.now().isBefore(ate);
  }

  /// Inicia timer + sync em background (nao bloqueia a abertura do app).
  Future<void> iniciar() async {
    await parar();
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva ||
        config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    _instanciaAtiva = this;
    _reconnectTentativa = 0;
    _revisionPendenteGrace = null;
    if (_plataformaCelular) {
      _graceAte = DateTime.now().add(_graceCelular);
    } else {
      _graceAte = null;
    }

    final intervaloBase = await SyncImplantacaoConfig(_configRepository)
        .intervaloSyncPeriodico();
    // Celular: um pouco mais espaçado (economiza bateria/rede).
    final intervaloEfetivo = _plataformaCelular
        ? Duration(
            milliseconds: (intervaloBase.inMilliseconds * 1.2).round(),
          )
        : intervaloBase;
    _timer = Timer.periodic(
      intervaloEfetivo,
      (_) => unawaited(sincronizarAgora(modo: SyncModo.periodico)),
    );
    unawaited(_conectarTempoReal());
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_enviarHeartbeat()),
    );
    unawaited(_enviarHeartbeat());
    unawaited(_consultarPresenca());

    // 1o sync automatico: bootstrap completo apos o grace (celular) / quase imediato (PC).
    final atrasoInicial =
        _plataformaCelular ? _graceCelular : const Duration(milliseconds: 300);
    unawaited(Future<void>(() async {
      await Future<void>.delayed(atrasoInicial);
      if (_instanciaAtiva != this) return;
      _graceAte = null;
      final pendente = _revisionPendenteGrace;
      _revisionPendenteGrace = null;
      await sincronizarAgora(modo: SyncModo.completo, forcar: true);
      if (pendente != null && _instanciaAtiva == this) {
        unawaited(_aoNovaRevisionRemota(pendente));
      }
    }));
  }

  /// App voltou ao foreground (Wi-Fi pode ter oscilado): reconecta WS + sync leve.
  static void aoRetomarApp() {
    final s = _instanciaAtiva;
    if (s == null) return;
    s._reconnectTentativa = 0;
    s._reconnectRealtimeTimer?.cancel();
    unawaited(s._conectarTempoReal());
    unawaited(s._enviarHeartbeat());
    unawaited(s.sincronizarAgora(modo: SyncModo.periodico, forcar: true));
  }

  Future<String> _rotuloEstacaoParaHeartbeat() async {
    final id = await _cursorStorage.obterOuCriarDeviceId();
    final sufixo = id.length >= 6 ? id.substring(0, 6) : id;
    if (kIsWeb) return 'web · $sufixo';
    try {
      if (Platform.isAndroid) return 'Android · $sufixo';
      if (Platform.isIOS) return 'iOS · $sufixo';
      if (Platform.isWindows) {
        final n = Platform.environment['COMPUTERNAME'];
        if (n != null && n.trim().isNotEmpty) {
          return '${n.trim()} · $sufixo';
        }
      }
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty) return '$host · $sufixo';
    } catch (_) {}
    return 'app · $sufixo';
  }

  Future<void> _enviarHeartbeat() async {
    if (_instanciaAtiva != this) return;
    final config = await _configRepository.carregarEmpresaConfig();
    if (!config.redeSincronizacaoAtiva || config.redeServidorUrl.trim().isEmpty) {
      return;
    }
    final client = SyncApiClient(
      baseUrl: config.redeServidorUrl,
      syncToken: config.redeSyncToken,
    );
    if (!client.configurado) return;
    try {
      final stationId = await _cursorStorage.obterOuCriarDeviceId();
      final resp = await client.heartbeat(
        stationId: stationId,
        label: await _rotuloEstacaoParaHeartbeat(),
      );
      if (resp == null) {
        SyncPresenceHub.instance.marcarIndisponivel();
        return;
      }
      if (resp.containsKey('activeCount')) {
        SyncPresenceHub.instance.aplicarMap(resp);
      } else {
        // Servidor antigo / corpo sem contagem: consulta /sync/presence.
        await _consultarPresenca(client: client);
      }
    } catch (_) {
      SyncPresenceHub.instance.marcarIndisponivel();
    }
  }

  Future<void> _consultarPresenca({SyncApiClient? client}) async {
    if (_instanciaAtiva != this) return;
    final SyncApiClient api;
    if (client != null) {
      api = client;
    } else {
      final config = await _configRepository.carregarEmpresaConfig();
      if (!config.redeSincronizacaoAtiva ||
          config.redeServidorUrl.trim().isEmpty) {
        return;
      }
      api = SyncApiClient(
        baseUrl: config.redeServidorUrl,
        syncToken: config.redeSyncToken,
      );
    }
    if (!api.configurado) return;
    try {
      final map = await api.obterPresenca();
      if (map == null) {
        SyncPresenceHub.instance.marcarIndisponivel();
        return;
      }
      SyncPresenceHub.instance.aplicarMap(map);
    } catch (_) {
      SyncPresenceHub.instance.marcarIndisponivel();
    }
  }

  Future<void> parar() async {
    if (_instanciaAtiva == this) {
      _instanciaAtiva = null;
    }
    _graceAte = null;
    _revisionPendenteGrace = null;
    _reconnectTentativa = 0;
    _timer?.cancel();
    _timer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectRealtimeTimer?.cancel();
    _reconnectRealtimeTimer = null;
    _debounceSyncEvento?.cancel();
    _debounceSyncEvento = null;
    _debounceSyncEscrita?.cancel();
    _debounceSyncEscrita = null;
    _debounceSyncPrioritario?.cancel();
    _debounceSyncPrioritario = null;
    if (_prioCompleter != null && !_prioCompleter!.isCompleted) {
      _prioCompleter!.complete();
    }
    _prioCompleter = null;
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

  Uri? _uriWebSocketDaBase(String raw, String syncToken) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) {
      s = 'http://$s';
    }
    final u = Uri.parse(s);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    final token = syncToken.trim();
    return Uri(
      scheme: scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: '/sync/stream',
      queryParameters: token.isNotEmpty
          ? {SyncAuth.queryParam: token}
          : null,
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
    final wsUri = _uriWebSocketDaBase(
      config.redeServidorUrl.trim(),
      config.redeSyncToken,
    );
    if (wsUri == null) return;
    try {
      if (kIsWeb) {
        _realtimeChannel = WebSocketChannel.connect(wsUri);
      } else {
        _realtimeChannel = IOWebSocketChannel.connect(
          wsUri,
          pingInterval: const Duration(seconds: 25),
        );
      }
      await _realtimeChannel!.ready.timeout(const Duration(seconds: 12));
      if (_instanciaAtiva != this) {
        await _fecharSomenteCanalWs();
        return;
      }
      _reconnectTentativa = 0;
      _realtimeSub = _realtimeChannel!.stream.listen(
        _aoReceberEventoTempoReal,
        onError: (_) => _agendarReconectarTempoReal(),
        onDone: _agendarReconectarTempoReal,
        cancelOnError: false,
      );
    } catch (_) {
      await _fecharSomenteCanalWs();
      _agendarReconectarTempoReal();
    }
  }

  void _agendarReconectarTempoReal() {
    if (_instanciaAtiva != this) return;
    _reconnectRealtimeTimer?.cancel();
    // Backoff + jitter: evita tempestade quando 2 celulares caem juntos.
    final exp = math.min(_reconnectTentativa, 5);
    final baseMs = (2000 * math.pow(2, exp)).round();
    const capMs = 60000;
    final delayMs = math.min(baseMs, capMs) + math.Random().nextInt(800);
    _reconnectTentativa++;
    _reconnectRealtimeTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_instanciaAtiva == this) {
        unawaited(_conectarTempoReal());
      }
    });
  }

  void _aoReceberEventoTempoReal(dynamic data) {
    _reconnectTentativa = 0;
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final tipo = (map['type'] ?? '').toString();
          if (tipo == 'presence') {
            SyncPresenceHub.instance.aplicarMap(map);
            return;
          }
          if (tipo == 'revision') {
            final remota = (map['revision'] as num?)?.toInt() ?? 0;
            unawaited(_aoNovaRevisionRemota(remota));
            return;
          }
        }
      } catch (_) {}
    }
    // Payload legado sem tipo: trata como "pode haver dados novos".
    unawaited(_aoNovaRevisionRemota(null));
  }

  /// So agenda sync se a revision remota for maior que a local.
  Future<void> _aoNovaRevisionRemota(int? remota) async {
    if (_plataformaCelular && _emGraceCelular) {
      if (remota != null) {
        final atual = _revisionPendenteGrace ?? 0;
        if (remota > atual) _revisionPendenteGrace = remota;
      } else {
        _revisionPendenteGrace ??= 0;
      }
      return;
    }

    if (remota != null) {
      final local = await _cursorStorage.carregarUltimaRevision();
      if (remota <= local) return;
    }

    _debounceSyncEvento?.cancel();
    if (_plataformaCelular) {
      _debounceSyncEvento = Timer(const Duration(seconds: 8), () {
        unawaited(sincronizarAgora(modo: SyncModo.periodico));
      });
      return;
    }

    final geracao = ++_debounceRedeGeracao;
    unawaited(_agendarSyncComDebounceRede(geracao: geracao));
  }

  Future<void> _agendarSyncComDebounceRede({required int geracao}) async {
    final debounce =
        await SyncImplantacaoConfig(_configRepository).debounceEventoRede();
    if (geracao != _debounceRedeGeracao || _instanciaAtiva != this) return;
    _debounceSyncEvento?.cancel();
    _debounceSyncEvento = Timer(debounce, () {
      if (geracao != _debounceRedeGeracao) return;
      unawaited(sincronizarAgora(modo: SyncModo.periodico));
    });
  }

  /// Apos gravacao de prioridade media (cadastros, entregas).
  static Future<void> solicitarSyncImediato() async {
    final scheduler = _instanciaAtiva;
    if (scheduler == null) return;
    if (_plataformaCelular) {
      _debounceSyncEscrita?.cancel();
      _debounceSyncEscrita = Timer(const Duration(seconds: 3), () {
        unawaited(
          scheduler.sincronizarAgora(modo: SyncModo.periodico, forcar: true),
        );
      });
      return;
    }
    final debounce = await SyncImplantacaoConfig(scheduler._configRepository)
        .debounceEventoRede();
    _debounceSyncEscrita?.cancel();
    _debounceSyncEscrita = Timer(debounce, () {
      unawaited(scheduler.sincronizarAgora(modo: SyncModo.periodico));
    });
  }

  /// Apos venda/estoque: push imediato (event-driven), serializado no mutex.
  /// Aguarda o ciclo terminar para o PDV so liberar depois do envio.
  ///
  /// Se houver chamada em debounce (ex.: dirty outbox + PDV), todos os waiters
  /// aguardam o **mesmo** ciclo final — nunca liberar o await anterior cedo,
  /// senao o PDV mostra o numero local antes do ACK `numeroCorrections`.
  static Future<void> solicitarSyncPrioritario() async {
    final scheduler = _instanciaAtiva;
    if (scheduler == null) return;
    // Coalesca gravações em rajada (itens) sem perder o await do ultimo ciclo.
    _debounceSyncPrioritario?.cancel();
    final anterior = _prioCompleter;
    final atual = Completer<void>();
    _prioCompleter = atual;
    // Quem esperava o debounce cancelado continua ate este ciclo terminar.
    if (anterior != null && !identical(anterior, atual)) {
      unawaited(
        atual.future.whenComplete(() {
          if (!anterior.isCompleted) anterior.complete();
        }),
      );
    }
    _debounceSyncPrioritario = Timer(
      SyncImplantacaoConfig.debouncePrioritario,
      () async {
        try {
          await scheduler.sincronizarAgora(
            modo: SyncModo.prioritario,
            forcar: true,
          );
        } finally {
          if (!atual.isCompleted) atual.complete();
          if (identical(_prioCompleter, atual)) {
            _prioCompleter = null;
          }
        }
      },
    );
    return atual.future;
  }

  static Completer<void>? _prioCompleter;

  /// Pull-to-refresh / botao manual: ciclo completo sem pular pull.
  static Future<String?> solicitarSyncCompleto() async {
    final scheduler = _instanciaAtiva;
    if (scheduler == null) return 'Sincronizacao de rede nao esta ativa.';
    return scheduler.sincronizarAgora(modo: SyncModo.completo, forcar: true);
  }

  /// Uma execucao (usada pelo timer e pelo botao em Configuracoes).
  /// [forcar] ignora a janela de grace do celular (botao manual / escrita local).
  Future<String?> sincronizarAgora({
    bool forcar = false,
    SyncModo modo = SyncModo.periodico,
  }) async {
    if (!forcar && _emGraceCelular) return null;

    final anterior = _mutexSync;
    final liberado = Completer<void>();
    _mutexSync = liberado.future;
    await anterior;
    try {
      final erro = await _syncService.executarSync(modo: modo);
      // Atualiza "N online" no rodape apos sync (sucesso ou falha de dados).
      unawaited(_enviarHeartbeat());
      // Celular novo ainda atrasado: continua puxando o catalogo.
      if (SyncService.consumirPedidoCatchupContinuo() &&
          _instanciaAtiva == this) {
        unawaited(Future<void>(() async {
          await Future<void>.delayed(const Duration(seconds: 2));
          if (_instanciaAtiva == this) {
            await sincronizarAgora(modo: SyncModo.completo, forcar: true);
          }
        }));
      }
      return erro;
    } finally {
      liberado.complete();
    }
  }

  /// PC: sobe JPEGs locais para o servidor (para o celular baixar sob demanda).
  Future<({int enviados, int ignorados, int falhas, String? detalhe})>
      enviarFotosProdutosAgora() {
    return _syncService.enviarFotosParaServidorAgora();
  }
}

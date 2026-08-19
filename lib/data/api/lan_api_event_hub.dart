import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../sync/sync_cursor_storage.dart';
import '../sync/sync_presence_hub.dart';
import 'lan_api_client.dart';

/// Escuta `/api/stream`, monitora health e bloqueia operacoes no terminal offline.
class LanApiEventHub extends ChangeNotifier {
  LanApiEventHub._();
  static final instance = LanApiEventHub._();

  static const msgServidorOffline =
      'Servidor offline. Verifique a conexão com o PC 1 para continuar vendendo.';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _healthTimer;
  Timer? _registerTimer;
  Timer? _notifyDebounce;
  LanApiClient? _client;
  String _ultimaEntidade = '';
  List<int> _ultimaEntidadeIds = const [];
  int _ultimaCatalogoRevision = 0;
  String _ultimoEventoTipo = '';
  Map<String, dynamic>? _ultimoEventoPayload;
  bool _online = false;
  bool _modoTerminal = false;
  bool _wsAtivo = false;
  bool _standby = false;
  String _stationId = '';
  String _label = '';
  int? _activeCount;
  List<String> _labels = const [];

  LanApiClient? get client => _client;

  String get ultimaEntidade => _ultimaEntidade;
  List<int> get ultimaEntidadeIds => _ultimaEntidadeIds;
  /// Revisao do catalogo enviada no ultimo evento `produto` (0 se ausente).
  int get ultimaCatalogoRevision => _ultimaCatalogoRevision;
  String get ultimoEventoTipo => _ultimoEventoTipo;
  Map<String, dynamic>? get ultimoEventoPayload => _ultimoEventoPayload;
  bool get online => _online;
  bool get modoTerminal => _modoTerminal;
  bool get emStandby => _standby;

  /// Terminais/celular com WS na API (mesmo [activeCount] do rodape do PC1).
  int? get activeCount => _activeCount;
  List<String> get labels => _labels;

  /// Recarrega GET /api/presence (rodape do terminal Windows/celular).
  Future<void> atualizarPresencaAgora() => _atualizarPresenca();

  /// Terminal leve sem API: bloquear busca/carrinho/finalizacao.
  bool get deveBloquearOperacoes => _modoTerminal && !_online;

  /// Mantem o client HTTP mas pausa WS e timers (login/menu em standby).
  void entrarStandby() {
    if (_standby) return;
    _standby = true;
    _fecharStream();
    _healthTimer?.cancel();
    _healthTimer = null;
    _registerTimer?.cancel();
    _registerTimer = null;
    _wsAtivo = false;
  }

  /// Retoma monitoramento apos login ou ao sair do standby.
  void sairStandby() {
    if (!_standby) return;
    _standby = false;
    final client = _client;
    if (client != null) {
      _iniciarStream(client);
      _reiniciarHealthTimer();
    }
  }

  void conectar(LanApiClient client, {bool terminalLeve = true}) {
    desconectar();
    _client = client;
    _modoTerminal = terminalLeve;
    _standby = false;
    _iniciarStream(client);
    unawaited(_pingHealth());
    _reiniciarHealthTimer();
  }

  void _iniciarStream(LanApiClient client) {
    // Evita subscription/canal orfaos apos queda silenciosa do WS.
    _fecharStream();
    final ch = client.abrirStream();
    if (ch == null) return;
    _channel = ch;
    _sub = ch.stream.listen(
      (raw) {
        try {
          final text = raw is String ? raw : utf8.decode(raw as List<int>);
          final map = jsonDecode(text);
          if (map is! Map) return;
          final type = map['type']?.toString();
          if (type == 'hello' ||
              type == 'entityChanged' ||
              type == 'novo_recado_chat' ||
              type == 'presence') {
            _wsAtivo = true;
            _setOnline(true);
          }
          if (type == 'hello') {
            unawaited(_enviarRegistro());
            unawaited(_atualizarPresenca());
          }
          if (type == 'presence') {
            _aplicarPresenca(Map<String, dynamic>.from(map));
            return;
          }
          if (type == 'novo_recado_chat') {
            _ultimoEventoTipo = 'novo_recado_chat';
            _ultimoEventoPayload = Map<String, dynamic>.from(map);
            _ultimaEntidade = 'chat_interno';
            notifyListeners();
            return;
          }
          if (type != 'entityChanged') return;
          _ultimoEventoTipo = 'entityChanged';
          _ultimoEventoPayload = null;
          _ultimaEntidade = (map['entity'] ?? '').toString();
          _ultimaEntidadeIds = _parseIds(map['ids']);
          final rev = map['revision'];
          if (rev is num) {
            _ultimaCatalogoRevision = rev.toInt();
          }
          _agendarNotifyListeners(prioridade: _ultimaEntidade == 'produto');
        } catch (_) {}
      },
      onError: (_) {
        // Ignora erro do canal antigo apos reconexao.
        if (!identical(_channel, ch)) return;
        _wsAtivo = false;
        _fecharStream();
        _setOnline(false);
      },
      onDone: () {
        if (!identical(_channel, ch)) return;
        _wsAtivo = false;
        _fecharStream();
        _setOnline(false);
      },
      cancelOnError: false,
    );
    unawaited(_enviarRegistro());
    _registerTimer?.cancel();
    _registerTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_enviarRegistro()),
    );
  }

  static List<int> _parseIds(Object? raw) {
    if (raw is! List) return const [];
    final out = <int>[];
    for (final e in raw) {
      final id = e is num ? e.toInt() : int.tryParse('$e') ?? 0;
      if (id > 0) out.add(id);
    }
    return out;
  }

  void _reiniciarHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_intervaloHealth, (_) {
      unawaited(_pingHealth());
    });
  }

  Duration get _intervaloHealth =>
      _wsAtivo ? const Duration(seconds: 45) : const Duration(seconds: 15);

  void _agendarNotifyListeners({bool prioridade = false}) {
    _notifyDebounce?.cancel();
    if (prioridade) {
      notifyListeners();
      return;
    }
    _notifyDebounce = Timer(const Duration(milliseconds: 250), () {
      notifyListeners();
    });
  }

  void desconectar() {
    _standby = false;
    _notifyDebounce?.cancel();
    _notifyDebounce = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _registerTimer?.cancel();
    _registerTimer = null;
    _fecharStream();
    _client = null;
    _modoTerminal = false;
    _wsAtivo = false;
    _ultimaEntidadeIds = const [];
    _setOnline(false);
  }

  void _fecharStream() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void marcarOnline() => _setOnline(true);

  void marcarOffline() => _setOnline(false);

  Future<void> _enviarRegistro() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      if (_stationId.isEmpty || _label.isEmpty) {
        _stationId = await SyncCursorStorage().obterOuCriarDeviceId();
        _label = await _rotuloEstacao();
      }
      ch.sink.add(
        jsonEncode({
          'type': 'register',
          'stationId': _stationId,
          'label': _label,
        }),
      );
    } catch (_) {}
  }

  Future<String> _rotuloEstacao() async {
    final id = _stationId.isNotEmpty
        ? _stationId
        : await SyncCursorStorage().obterOuCriarDeviceId();
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
    return 'Terminal · $sufixo';
  }

  Future<void> _pingHealth() async {
    if (_standby) return;
    final client = _client;
    if (client == null || !client.configurado) {
      _setOnline(false);
      return;
    }
    final ok = await client.healthOk();
    if (ok != _online) {
      _setOnline(ok);
    }
    if (ok) {
      unawaited(_atualizarPresenca());
    }
    // Celular: WS cai com frequencia; HTTP continua. Sem limpar o canal na
    // queda, o health nunca reconectava — preco/estoque no PDV so atualizavam
    // ao abrir Cadastro (hidratar HTTP).
    if (ok && !_wsAtivo && _channel == null && !_standby) {
      _iniciarStream(client);
    }
  }

  Future<void> _atualizarPresenca() async {
    final client = _client;
    if (client == null || _standby) return;
    final map = await client.obterPresenca();
    if (map == null) return;
    _aplicarPresenca(map);
  }

  void _aplicarPresenca(Map<String, dynamic> map) {
    final n = (map['activeCount'] as num?)?.toInt();
    if (n == null) return;
    final rotulos = <String>[];
    final raw = map['stations'];
    if (raw is List) {
      for (final e in raw) {
        final m = e is Map<String, dynamic>
            ? e
            : e is Map
                ? Map<String, dynamic>.from(e)
                : null;
        if (m == null) continue;
        final lab = (m['label'] ?? '').toString().trim();
        rotulos.add(lab.isEmpty ? 'Terminal' : lab);
      }
    }
    if (_activeCount == n && listEquals(_labels, rotulos)) return;
    _activeCount = n;
    _labels = List<String>.unmodifiable(rotulos);
    try {
      SyncPresenceHub.instance.aplicarMap(map);
    } catch (_) {}
    notifyListeners();
  }

  void _setOnline(bool value) {
    if (_online == value) {
      return;
    }
    _online = value;
    if (!value) {
      _activeCount = null;
      _labels = const [];
      try {
        SyncPresenceHub.instance.marcarIndisponivel();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Retorna false e mostra SnackBar se o terminal estiver sem servidor.
  bool garantirOnlineOuAvisar(BuildContext context) {
    if (!deveBloquearOperacoes) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(msgServidorOffline),
        duration: Duration(seconds: 4),
      ),
    );
    return false;
  }
}

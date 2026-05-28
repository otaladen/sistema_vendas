import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_auth.dart';

class SyncApiClient {
  SyncApiClient({
    required String baseUrl,
    String syncToken = '',
  })  : _base = _normalizarBase(baseUrl),
        _syncToken = syncToken.trim();

  final String _base;
  final String _syncToken;

  static String _normalizarBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  bool get configurado => _base.isNotEmpty;

  /// Host e porta parseados do [baseUrl] (para teste de socket).
  (String, int)? get hostPorta {
    if (!configurado) return null;
    final u = Uri.parse(_base);
    if (u.host.isEmpty) return null;
    final porta = u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80);
    return (u.host, porta);
  }

  /// GET `/sync/meta` com ou sem header de token (diagnostico LAN).
  Future<int> metaStatus({required bool incluirToken}) async {
    if (!configurado) return 0;
    try {
      final headers = incluirToken && _syncToken.isNotEmpty
          ? {SyncAuth.headerName: _syncToken}
          : null;
      final r = await http
          .get(_uri('/sync/meta'), headers: headers)
          .timeout(const Duration(seconds: 8));
      return r.statusCode;
    } catch (_) {
      return 0;
    }
  }

  Map<String, String> _headersJson() {
    final h = <String, String>{'content-type': 'application/json'};
    if (_syncToken.isNotEmpty) {
      h[SyncAuth.headerName] = _syncToken;
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{};
    if (query != null) q.addAll(query);
    if (_syncToken.isNotEmpty) {
      q[SyncAuth.queryParam] = _syncToken;
    }
    final u = Uri.parse('$_base$path');
    if (q.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  Future<bool> health() async {
    if (!configurado) return false;
    try {
      final r = await http
          .get(_uri('/health'))
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Heartbeat para o servidor contar estacoes com o app aberto (LAN).
  Future<bool> heartbeat({
    required String stationId,
    required String label,
  }) async {
    if (!configurado) return false;
    try {
      final r = await http
          .post(
            _uri('/sync/heartbeat'),
            headers: _headersJson(),
            body: jsonEncode({
              'stationId': stationId,
              'label': label,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Estacoes que enviaram heartbeat nos ultimos [ttlSeconds] do servidor.
  Future<Map<String, dynamic>?> obterPresenca() async {
    if (!configurado) return null;
    try {
      final r =
          await http.get(_uri('/sync/presence')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> pull({
    required int since,
    required String deviceId,
    int limit = 2000,
  }) async {
    final r = await http
        .get(
          _uri('/sync/pull', {
            'since': '$since',
            'deviceId': deviceId,
            'limit': '$limit',
          }),
          headers: _syncToken.isNotEmpty
              ? {SyncAuth.headerName: _syncToken}
              : null,
        )
        .timeout(const Duration(seconds: 120));
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw StateError(
        'Sync recusado pelo servidor (token invalido ou ausente). '
        'Configure o mesmo token em Configuracoes > Rede.',
      );
    }
    if (r.statusCode != 200) {
      throw StateError('pull HTTP ${r.statusCode}: ${r.body}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('pull: resposta invalida');
    }
    return decoded;
  }

  /// POST `/sync/pod` — envia JPEG (base64) para pasta central do servidor.
  Future<String?> uploadPodFoto({
    required String fileName,
    required List<int> jpegBytes,
  }) async {
    if (!configurado) return null;
    try {
      final r = await http
          .post(
            _uri('/sync/pod'),
            headers: _headersJson(),
            body: jsonEncode({
              'fileName': fileName,
              'contentBase64': base64Encode(jpegBytes),
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['ok'] != true) return null;
      return (decoded['path'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  /// GET `/sync/pod/<fileName>` — baixa JPEG do servidor.
  Future<List<int>?> downloadPodFoto({required String fileName}) async {
    if (!configurado) return null;
    try {
      final r = await http
          .get(
            _uri('/sync/pod/$fileName'),
            headers: _syncToken.isNotEmpty
                ? {SyncAuth.headerName: _syncToken}
                : null,
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> push({
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    final r = await http
        .post(
          _uri('/sync/push'),
          headers: _headersJson(),
          body: jsonEncode({
            'deviceId': deviceId,
            'mutations': mutations,
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw StateError(
        'Sync recusado pelo servidor (token invalido ou ausente).',
      );
    }
    if (r.statusCode != 200) {
      throw StateError('push HTTP ${r.statusCode}: ${r.body}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('push: resposta invalida');
    }
    return decoded;
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

class SyncApiClient {
  SyncApiClient({required String baseUrl}) : _base = _normalizarBase(baseUrl);

  final String _base;

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

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$_base$path');
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Future<bool> health() async {
    if (!configurado) return false;
    try {
      final r = await http.get(_uri('/health')).timeout(const Duration(seconds: 8));
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
            headers: {'content-type': 'application/json'},
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
        )
        .timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) {
      throw StateError('pull HTTP ${r.statusCode}: ${r.body}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('pull: resposta invalida');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> push({
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    final r = await http
        .post(
          _uri('/sync/push'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'mutations': mutations,
          }),
        )
        .timeout(const Duration(seconds: 120));
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

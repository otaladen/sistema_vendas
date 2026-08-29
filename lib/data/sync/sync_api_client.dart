import 'dart:convert';
import 'dart:isolate';

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
    final u = Uri.parse('$_base$path');
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  /// GET `/sync/version` — leve: so lastRevision (cliente evita pull pesado).
  /// Fallback: `/sync/meta.lastRevision` em servidores antigos.
  Future<({int lastRevision, int schemaVersion})?> obterVersao() async {
    if (!configurado) return null;
    try {
      final r = await http
          .get(_uri('/sync/version'), headers: _headersJson())
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final map = jsonDecode(r.body);
        if (map is Map) {
          return (
            lastRevision: (map['lastRevision'] as num?)?.toInt() ?? 0,
            schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 0,
          );
        }
      }
    } catch (_) {
      // Servidor antigo sem /sync/version — tenta meta.
    }
    try {
      final meta = await obterMeta();
      if (meta == null) return null;
      return (
        lastRevision: (meta['lastRevision'] as num?)?.toInt() ?? 0,
        schemaVersion: (meta['schemaVersion'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
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
  /// Retorna o snapshot de presenca quando o servidor envia (versoes novas).
  Future<Map<String, dynamic>?> heartbeat({
    required String stationId,
    required String label,
  }) async {
    if (!configurado) return null;
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
      if (r.statusCode != 200) return null;
      try {
        final decoded = jsonDecode(r.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return const {'ok': true};
    } catch (_) {
      return null;
    }
  }

  /// Estacoes que enviaram heartbeat nos ultimos [ttlSeconds] do servidor.
  Future<Map<String, dynamic>?> obterPresenca() async {
    if (!configurado) return null;
    try {
      final r =
          await http.get(_uri('/sync/presence'), headers: _headersJson()).timeout(const Duration(seconds: 8));
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
    /// Carga inicial do celular: servidor aplica pruning (produtos ativos,
    /// orcamentos abertos/recentes) e lotes maiores.
    bool bootstrap = false,
  }) async {
    final r = await http
        .get(
          _uri('/sync/pull', {
            'since': '$since',
            'deviceId': deviceId,
            'limit': '$limit',
            if (bootstrap) 'bootstrap': '1',
          }),
          headers: _headersJson(),
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
    final body = r.body;
    return Isolate.run(() {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw StateError('pull: resposta invalida');
      }
      return Map<String, dynamic>.from(decoded);
    });
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
            headers: _headersJson(),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// GET `/sync/meta` — metadados do servidor (inclui pasta de fotos quando disponivel).
  Future<Map<String, dynamic>?> obterMeta() async {
    if (!configurado) return null;
    try {
      final r = await http
          .get(_uri('/sync/meta'), headers: _headersJson())
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// POST `/sync/product-image` — envia JPEG de produto para pasta do servidor.
  /// Retorna path ou null; [ultimoErro] recebe detalhe da falha.
  Future<String?> uploadProductImage({
    required String fileName,
    required List<int> jpegBytes,
    void Function(String motivo)? onErro,
  }) async {
    if (!configurado) {
      onErro?.call('URL do servidor vazia.');
      return null;
    }
    try {
      final r = await http
          .post(
            _uri('/sync/product-image'),
            headers: _headersJson(),
            body: jsonEncode({
              'fileName': fileName,
              'contentBase64': base64Encode(jpegBytes),
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (r.statusCode == 401 || r.statusCode == 403) {
        onErro?.call('Token de sync recusado (HTTP ${r.statusCode}).');
        return null;
      }
      if (r.statusCode == 404) {
        onErro?.call(
          'Servidor sem rota de fotos. Atualize o app no PC servidor.',
        );
        return null;
      }
      if (r.statusCode != 200) {
        onErro?.call('Upload HTTP ${r.statusCode}: ${r.body}');
        return null;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) {
        onErro?.call('Resposta invalida do servidor.');
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);
      if (map['ok'] != true) {
        onErro?.call((map['error'] ?? 'upload_falhou').toString());
        return null;
      }
      return (map['path'] ?? '').toString();
    } catch (e) {
      onErro?.call('$e');
      return null;
    }
  }

  /// GET `/sync/product-image/<fileName>` — baixa JPEG de produto.
  Future<List<int>?> downloadProductImage({required String fileName}) async {
    if (!configurado) return null;
    final nome = fileName.trim();
    if (nome.isEmpty) return null;
    Future<List<int>?> tentar(String pathSuffix) async {
      try {
        final r = await http
            .get(
              _uri('/sync/product-image/$pathSuffix'),
              headers: _headersJson(),
            )
            .timeout(const Duration(seconds: 60));
        if (r.statusCode != 200) return null;
        if (r.bodyBytes.isEmpty) return null;
        final ct = r.headers['content-type'] ?? '';
        if (ct.contains('application/json')) return null;
        return r.bodyBytes;
      } catch (_) {
        return null;
      }
    }

    // 1) path simples  2) encoded (nomes com espaco etc.)
    return await tentar(nome) ?? await tentar(Uri.encodeComponent(nome));
  }

  Future<Map<String, dynamic>> push({
    required String deviceId,
    required List<Map<String, dynamic>> mutations,
    String? pushBatchId,
  }) async {
    final batch = pushBatchId?.trim();
    final body = await Isolate.run(() {
      return jsonEncode({
        'deviceId': deviceId,
        'mutations': mutations,
        if (batch != null && batch.isNotEmpty) 'pushBatchId': batch,
      });
    });
    final r = await http
        .post(
          _uri('/sync/push'),
          headers: _headersJson(),
          body: body,
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
    final respBody = r.body;
    return Isolate.run(() {
      final decoded = jsonDecode(respBody);
      if (decoded is! Map) {
        throw StateError('push: resposta invalida');
      }
      return Map<String, dynamic>.from(decoded);
    });
  }
}

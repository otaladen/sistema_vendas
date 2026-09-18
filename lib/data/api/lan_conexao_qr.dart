import 'dart:convert';

import 'lan_api_url.dart';

/// Payload do QR de conexao do celular (Wi-Fi / Tailscale + token).
class LanConexaoQrDados {
  const LanConexaoQrDados({
    required this.url,
    required this.token,
  });

  final String url;
  final String token;
}

/// Serializa/le o QR usado em Configuracoes > Rede e no Terminal Leve.
abstract final class LanConexaoQr {
  LanConexaoQr._();

  static String montar({
    required String url,
    required String token,
  }) {
    final api = LanApiUrl.fromSyncUrl(url);
    return jsonEncode({
      'v': 1,
      'url': api,
      'token': token.trim(),
    });
  }

  static LanConexaoQrDados? parse(String bruto) {
    final t = bruto.trim();
    if (t.isEmpty) return null;

    if (t.startsWith('{')) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is! Map) return null;
        final url = LanApiUrl.fromSyncUrl('${decoded['url'] ?? ''}');
        if (url.isEmpty) return null;
        return LanConexaoQrDados(
          url: url,
          token: '${decoded['token'] ?? ''}'.trim(),
        );
      } catch (_) {
        return null;
      }
    }

    if (!t.contains('://') && !t.contains(':')) return null;
    final url = LanApiUrl.fromSyncUrl(t);
    if (url.isEmpty) return null;
    return LanConexaoQrDados(url: url, token: '');
  }
}

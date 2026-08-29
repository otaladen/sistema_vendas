import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/api/lan_api_url.dart';
import '../data/sync/sync_auth.dart';

/// Utilitarios de rede local do PC servidor (API :8788).
///
/// O hub mobile :8787 foi removido: celular e terminal Windows usam a mesma API.
abstract final class LanRedeHelper {
  LanRedeHelper._();

  static String montarUrlServidor(
    String host, {
    int porta = LanApiUrl.portaPadrao,
  }) {
    final h = host.trim();
    if (h.isEmpty) return '';
    return 'http://$h:$porta';
  }

  /// IPv4 privado deste PC na LAN (nao loopback).
  static Future<String?> obterIpv4Local() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      String? fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          if (_ipPrivadoLan(ip)) return ip;
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  static bool _ipPrivadoLan(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final segundo = int.tryParse(parts[1]) ?? 0;
        if (segundo >= 16 && segundo <= 31) return true;
      }
    }
    return false;
  }

  /// Pasta de fotos do app (mesmo local usado pelo ObjectBox).
  static Future<String> caminhoPadraoProductImages() async {
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    return p.join(baseDir.path, 'product_images');
  }

  /// GET /api/health na API de terminais.
  static Future<bool> apiRespondendo({
    String? baseUrl,
    int porta = LanApiUrl.portaPadrao,
    String syncToken = '',
  }) async {
    final candidatos = <String>[];
    final raw = (baseUrl ?? '').trim();
    if (raw.isNotEmpty) {
      candidatos.add(LanApiUrl.fromSyncUrl(raw, portaApi: porta));
    }
    candidatos.add(LanApiUrl.local(porta));
    candidatos.add('http://localhost:$porta');

    final vistos = <String>{};
    for (final url in candidatos) {
      if (url.isEmpty || !vistos.add(url)) continue;
      if (await _healthOk(url, syncToken)) return true;
    }
    return false;
  }

  static Future<bool> _healthOk(String base, String token) async {
    try {
      final uri = Uri.parse('$base/api/health');
      final headers = <String, String>{};
      final t = token.trim();
      if (t.isNotEmpty) headers[SyncAuth.headerName] = t;
      final r = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 3));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Cria regra de firewall para a porta da API (requer admin).
  static Future<String?> tentarLiberarFirewall({
    int porta = LanApiUrl.portaPadrao,
  }) async {
    if (!Platform.isWindows) {
      return 'Disponivel apenas no Windows.';
    }
    try {
      final r = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=Sistema Vendas API (TCP $porta)',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$porta',
      ], runInShell: true);
      if (r.exitCode == 0) return null;
      return 'Nao foi possivel criar a regra (codigo ${r.exitCode}). '
          'Execute o app como administrador ou libere a porta $porta '
          'manualmente no Firewall do Windows.';
    } catch (e) {
      return 'Erro ao configurar firewall: $e';
    }
  }

  /// Encerra o exe antigo do hub :8787, se ainda estiver rodando.
  static Future<void> encerrarHubLegadoSeExistir() async {
    if (!Platform.isWindows) return;
    for (final nome in const [
      'sistema_vendas_sync_server.exe',
      'sistema_vendas_sync_server_presenca.exe',
      'sistema_vendas_sync_server_novo.exe',
    ]) {
      try {
        await Process.run('taskkill', ['/IM', nome, '/F']);
      } catch (_) {}
    }
  }
}

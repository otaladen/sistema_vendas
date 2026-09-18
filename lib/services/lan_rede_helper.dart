import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/api/lan_api_url.dart';
import '../data/api/lan_conexao_perfis.dart';
import '../data/sync/sync_auth.dart';
import 'lan_endereco_local.dart';

export 'lan_endereco_local.dart';

/// Utilitarios de rede local do PC servidor (API :8788).
///
/// O hub mobile :8787 foi removido: celular e terminal Windows usam a mesma API.
/// O HTTP escuta em 0.0.0.0:8788; estes metodos so listam IPs para a UI.
abstract final class LanRedeHelper {
  LanRedeHelper._();

  static String montarUrlServidor(
    String host, {
    int porta = LanApiUrl.portaPadrao,
  }) {
    return LanApiUrl.fromSyncUrl(host, portaApi: porta);
  }

  /// IPv4 recomendado para PCs da loja (Ethernet / LAN privada).
  static Future<String?> obterIpv4Local() async {
    final lista = await listarEnderecosAtivos();
    return enderecoRecomendadoPcs(lista)?.ip ??
        (lista.isEmpty ? null : lista.first.ip);
  }

  /// Placas IPv4 ativas (Ethernet, Wi-Fi, Tailscale), sem loopback/virtuais.
  static Future<List<LanEnderecoLocal>> listarEnderecosAtivos({
    int porta = LanApiUrl.portaPadrao,
  }) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final lista = <LanEnderecoLocal>[];
      final vistos = <String>{};
      for (final iface in interfaces) {
        if (deveIgnorarInterface(iface.name)) continue;
        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (ip.isEmpty || ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }
          if (!vistos.add(ip)) continue;
          final tipo = classificarInterface(
            nomeInterface: iface.name,
            ip: ip,
          );
          lista.add(
            LanEnderecoLocal(
              nomeInterface: iface.name,
              ip: ip,
              tipo: tipo,
              url: montarUrlServidor(ip, porta: porta),
            ),
          );
        }
      }
      lista.sort(_ordenarEnderecos);
      final recomendado = enderecoRecomendadoPcs(lista);
      return [
        for (final e in lista)
          LanEnderecoLocal(
            nomeInterface: e.nomeInterface,
            ip: e.ip,
            tipo: e.tipo,
            url: e.url,
            recomendadoPcs: recomendado != null &&
                e.ip == recomendado.ip &&
                e.tipo == recomendado.tipo,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static LanEnderecoLocal? enderecoRecomendadoPcs(
    List<LanEnderecoLocal> lista,
  ) {
    for (final e in lista) {
      if (e.tipo == LanInterfaceTipo.ethernet) return e;
    }
    for (final e in lista) {
      if (e.tipo != LanInterfaceTipo.tailscale && e.tipo != LanInterfaceTipo.wifi) {
        return e;
      }
    }
    for (final e in lista) {
      if (e.tipo == LanInterfaceTipo.wifi) return e;
    }
    return lista.isEmpty ? null : lista.first;
  }

  /// Preferencia do QR do celular: Wi-Fi da loja, senao Tailscale.
  static List<LanEnderecoLocal> enderecosParaCelular(
    List<LanEnderecoLocal> lista,
  ) {
    final wifi = lista.where((e) => e.tipo == LanInterfaceTipo.wifi).toList();
    final tail = lista.where((e) => e.tipo == LanInterfaceTipo.tailscale).toList();
    if (wifi.isNotEmpty || tail.isNotEmpty) {
      return [...wifi, ...tail];
    }
    // Mesma LAN: celular no Wi-Fi do roteador alcanca o IP cabeado do PC.
    return [
      for (final e in lista)
        if (e.tipo == LanInterfaceTipo.ethernet) e,
    ];
  }

  static bool deveIgnorarInterface(String nome) {
    final n = nome.toLowerCase();
    const skip = [
      'loopback',
      'bluetooth',
      'isatap',
      'teredo',
      'vethernet',
      'hyper-v',
      'virtualbox',
      'vmware',
      'docker',
      'wsl',
      'pseudo-interface',
      'default switch',
    ];
    return skip.any(n.contains);
  }

  static LanInterfaceTipo classificarInterface({
    required String nomeInterface,
    required String ip,
  }) {
    final n = nomeInterface.toLowerCase();
    if (LanConexaoPerfisStore.pareceTailscale(ip) ||
        n.contains('tailscale') ||
        n.contains('tail-scale')) {
      return LanInterfaceTipo.tailscale;
    }
    if (n.contains('wi-fi') ||
        n.contains('wifi') ||
        n.contains('wlan') ||
        n.contains('wireless') ||
        n.contains('802.11')) {
      return LanInterfaceTipo.wifi;
    }
    if (n.contains('ethernet') ||
        n.contains('gigabit') ||
        n.contains('local area') ||
        n.contains('area local') ||
        n.contains('área local') ||
        n.contains('conexao local') ||
        n.contains('conexão local') ||
        RegExp(r'(^|[^a-z])eth(\d+)?($|[^a-z])').hasMatch(n)) {
      return LanInterfaceTipo.ethernet;
    }
    if (ipPrivadoLan(ip)) return LanInterfaceTipo.ethernet;
    return LanInterfaceTipo.outra;
  }

  static int _ordenarEnderecos(LanEnderecoLocal a, LanEnderecoLocal b) {
    int peso(LanInterfaceTipo t) {
      switch (t) {
        case LanInterfaceTipo.ethernet:
          return 0;
        case LanInterfaceTipo.wifi:
          return 1;
        case LanInterfaceTipo.tailscale:
          return 2;
        case LanInterfaceTipo.outra:
          return 3;
      }
    }

    final c = peso(a.tipo).compareTo(peso(b.tipo));
    if (c != 0) return c;
    return a.ip.compareTo(b.ip);
  }

  static bool ipPrivadoLan(String ip) => _ipPrivadoLan(ip);

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

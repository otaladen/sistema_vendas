import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync/sync_api_client.dart';

/// Localiza, inicia e monitora o `sistema_vendas_sync_server` no Windows.
class LanSyncServerManager {
  static const _kPid = 'lan_sync_server_pid';
  static const portaPadrao = 8787;

  /// Mesma pasta usada pelo ObjectBox para fotos de produto.
  static Future<String> caminhoPadraoProductImages() async {
    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    return p.join(baseDir.path, 'product_images');
  }

  /// Caminhos possiveis do executavel (instalacao e desenvolvimento).
  static Future<String?> localizarExecutavel() async {
    final candidatos = <String>[];

    void adicionarEm(String base) {
      candidatos.add(
        p.join(base, 'sync_server', 'sistema_vendas_sync_server.exe'),
      );
      candidatos.add(
        p.join(base, 'sync_server', 'sistema_vendas_sync_server_presenca.exe'),
      );
      candidatos.add(
        p.join(base, 'sync_server', 'sistema_vendas_sync_server_novo.exe'),
      );
      candidatos.add(p.join(base, 'sistema_vendas_sync_server.exe'));
      candidatos.add(p.join(base, 'sistema_vendas_sync_server_presenca.exe'));
      candidatos.add(p.join(base, 'sistema_vendas_sync_server_novo.exe'));
    }

    void subirPastas(Directory start, {int maxNiveis = 10}) {
      var dir = start;
      for (var i = 0; i < maxNiveis; i++) {
        adicionarEm(dir.path);
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }

    try {
      final exeDir = Directory(File(Platform.resolvedExecutable).parent.path);
      // Prioridade: pasta ao lado do .exe (instalacao / Release).
      adicionarEm(exeDir.path);
      // Depois sobe a arvore (ex.: Release → … → raiz do projeto no dev).
      subirPastas(exeDir.parent);
    } catch (_) {}

    try {
      subirPastas(Directory.current);
    } catch (_) {}

    final vistos = <String>{};
    for (final c in candidatos) {
      final norm = p.normalize(c);
      if (!vistos.add(norm.toLowerCase())) continue;
      if (File(norm).existsSync()) return norm;
    }
    return null;
  }

  static String montarUrlServidor(String host, int porta) {
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

  static Future<bool> servidorRespondendo(String baseUrl) async {
    return SyncApiClient(baseUrl: baseUrl).health();
  }

  static Future<bool> servidorRespondendoNaPorta(int porta) async {
    if (await servidorRespondendo('http://127.0.0.1:$porta')) return true;
    return servidorRespondendo('http://localhost:$porta');
  }

  /// Encerra o processo gravado e qualquer sync_server residual na porta.
  static Future<void> pararServidor() async {
    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_kPid);
    if (pid != null && pid > 0) {
      try {
        await Process.run('taskkill', ['/PID', '$pid', '/F']);
      } catch (_) {}
      await prefs.remove(_kPid);
    }
    // Mata exes residuais (abertos a mao / sessao antiga) que apontam pasta errada.
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

  /// Inicia o processo do servidor (Windows). Retorna mensagem de erro ou null se OK.
  ///
  /// Sempre define [SYNC_PRODUCT_IMAGES_PATH] para a pasta de fotos do app —
  /// senao o exe usa uma pasta vazia ao lado dele e o celular toma "foto indisponivel"
  /// mesmo com as imagens aparecendo no PC.
  static Future<String?> iniciarServidor({
    int porta = portaPadrao,
    String syncToken = '',
    String? productImagesPath,
  }) async {
    if (!Platform.isWindows) {
      return 'Iniciar servidor pelo app so esta disponivel no Windows.';
    }

    final fotos = (productImagesPath ?? await caminhoPadraoProductImages()).trim();
    final exe = await localizarExecutavel();
    final jaOnline = await servidorRespondendoNaPorta(porta);

    // Sem exe: nao derruba hub que ja esteja rodando (ex.: iniciado a mao).
    if (exe == null) {
      if (jaOnline) return null;
      return 'Hub mobile (:$porta): executavel nao encontrado.\n'
          'Copie a pasta sync_server para ao lado do sistema_vendas.exe '
          '(com sistema_vendas_sync_server.exe), ou rode '
          'sync_server\\build_windows_exe.bat no projeto.\n'
          'Obs.: terminais Windows usam a API :8788 — o hub mobile e opcional.';
    }

    // Sempre reinicia: garante a pasta correta de fotos do app.
    if (jaOnline) {
      await pararServidor();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    try {
      final env = Map<String, String>.from(Platform.environment);
      final token = syncToken.trim();
      if (token.isNotEmpty) {
        env['SYNC_TOKEN'] = token;
        env['SYNC_REQUIRE_TOKEN'] = '1';
      }
      if (fotos.isNotEmpty) {
        env['SYNC_PRODUCT_IMAGES_PATH'] = fotos;
        Directory(fotos).createSync(recursive: true);
      }
      final process = await Process.start(
        exe,
        ['$porta'],
        mode: ProcessStartMode.detached,
        workingDirectory: File(exe).parent.path,
        environment: env,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPid, process.pid);

      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await servidorRespondendoNaPorta(porta)) {
          return null;
        }
      }
      return 'Hub mobile iniciado, mas ainda nao respondeu na porta $porta. '
          'Verifique o firewall do Windows.';
    } catch (e) {
      return 'Nao foi possivel iniciar o hub mobile: $e';
    }
  }

  /// Tenta criar regra de firewall para a porta (requer admin).
  static Future<String?> tentarLiberarFirewall(int porta) async {
    if (!Platform.isWindows) {
      return 'Disponivel apenas no Windows.';
    }
    try {
      final r = await Process.run('netsh', [
        'advfirewall',
        'firewall',
        'add',
        'rule',
        'name=Sistema Vendas Sync (TCP $porta)',
        'dir=in',
        'action=allow',
        'protocol=TCP',
        'localport=$porta',
      ], runInShell: true);
      if (r.exitCode == 0) return null;
      return 'Nao foi possivel criar a regra (codigo ${r.exitCode}). '
          'Execute o app como administrador ou libere a porta $porta manualmente '
          'no Firewall do Windows.';
    } catch (e) {
      return 'Erro ao configurar firewall: $e';
    }
  }
}

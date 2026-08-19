import 'package:shared_preferences/shared_preferences.dart';

import 'lan_api_url.dart';

/// Perfis rapidos de conexao do Terminal Leve / Modo Motorista.
enum LanConexaoPerfil {
  wifiLoja,
  tailscale4g,
}

/// Persiste URLs Wi-Fi local e Tailscale (4G) + perfil ativo.
abstract final class LanConexaoPerfisStore {
  LanConexaoPerfisStore._();

  static const _kPerfil = 'lan_conexao_perfil_ativo';
  static const _kWifi = 'lan_conexao_url_wifi';
  static const _kTail = 'lan_conexao_url_tailscale';

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<LanConexaoPerfil> perfilAtivo() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_kPerfil) ?? '';
    return raw == LanConexaoPerfil.tailscale4g.name
        ? LanConexaoPerfil.tailscale4g
        : LanConexaoPerfil.wifiLoja;
  }

  static Future<void> setPerfilAtivo(LanConexaoPerfil perfil) async {
    final prefs = await _prefs;
    await prefs.setString(_kPerfil, perfil.name);
  }

  static Future<String> urlWifi() async {
    final prefs = await _prefs;
    return (prefs.getString(_kWifi) ?? '').trim();
  }

  static Future<String> urlTailscale() async {
    final prefs = await _prefs;
    return (prefs.getString(_kTail) ?? '').trim();
  }

  static Future<String> urlDoPerfil(LanConexaoPerfil perfil) async {
    switch (perfil) {
      case LanConexaoPerfil.wifiLoja:
        return urlWifi();
      case LanConexaoPerfil.tailscale4g:
        return urlTailscale();
    }
  }

  static Future<String> urlAtiva() async {
    final p = await perfilAtivo();
    return urlDoPerfil(p);
  }

  static Future<void> salvarUrlPerfil(
    LanConexaoPerfil perfil,
    String url,
  ) async {
    final normalizada = LanApiUrl.fromSyncUrl(url);
    final prefs = await _prefs;
    if (perfil == LanConexaoPerfil.wifiLoja) {
      await prefs.setString(_kWifi, normalizada);
    } else {
      await prefs.setString(_kTail, normalizada);
    }
  }

  /// Se ainda nao ha perfil gravado, classifica [urlAtual] e grava.
  static Future<void> migrarSeVazio(String urlAtual) async {
    final normalizada = LanApiUrl.fromSyncUrl(urlAtual);
    if (normalizada.isEmpty) return;
    final wifi = await urlWifi();
    final tail = await urlTailscale();
    if (wifi.isNotEmpty || tail.isNotEmpty) return;
    if (pareceTailscale(normalizada)) {
      await salvarUrlPerfil(LanConexaoPerfil.tailscale4g, normalizada);
      await setPerfilAtivo(LanConexaoPerfil.tailscale4g);
    } else {
      await salvarUrlPerfil(LanConexaoPerfil.wifiLoja, normalizada);
      await setPerfilAtivo(LanConexaoPerfil.wifiLoja);
    }
  }

  /// IPs Tailscale tipicamente em 100.64.0.0/10 (CGNAT).
  static bool pareceTailscale(String url) {
    final u = Uri.tryParse(
      url.contains('://') ? url.trim() : 'http://${url.trim()}',
    );
    final host = u?.host.trim() ?? '';
    if (host.isEmpty) return false;
    if (host.toLowerCase().contains('ts.net')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    // 100.64.0.0 – 100.127.255.255
    return a == 100 && b >= 64 && b <= 127;
  }

  static String rotulo(LanConexaoPerfil perfil) {
    switch (perfil) {
      case LanConexaoPerfil.wifiLoja:
        return 'Wi-Fi Loja (Local)';
      case LanConexaoPerfil.tailscale4g:
        return 'Rede Externa (Tailscale 4G)';
    }
  }

  static String iconeEmoji(LanConexaoPerfil perfil) {
    switch (perfil) {
      case LanConexaoPerfil.wifiLoja:
        return '🏠';
      case LanConexaoPerfil.tailscale4g:
        return '🚚';
    }
  }

  static String hint(LanConexaoPerfil perfil) {
    switch (perfil) {
      case LanConexaoPerfil.wifiLoja:
        return 'http://192.168.0.10:${LanApiUrl.portaPadrao}';
      case LanConexaoPerfil.tailscale4g:
        return 'http://100.x.x.x:${LanApiUrl.portaPadrao}';
    }
  }
}

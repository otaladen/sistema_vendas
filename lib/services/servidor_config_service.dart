import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/api/lan_api_url.dart';

/// Validacao de URL do PC servidor (terminal leve / sync no celular).
abstract final class ServidorConfigService {
  ServidorConfigService._();

  static bool get _ehDispositivoMovel =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// True se o host aponta para a propria maquina (inutil no celular).
  static bool hostInacessivelNoMobile(String syncOuApiUrl) {
    final api = LanApiUrl.fromSyncUrl(syncOuApiUrl.trim());
    if (api.isEmpty) return false;
    final host = Uri.parse(api).host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0';
  }

  /// Mensagem amigavel ou null se OK para este dispositivo.
  static String? validarUrlParaDispositivo(String syncOuApiUrl) {
    if (!_ehDispositivoMovel) return null;
    if (!hostInacessivelNoMobile(syncOuApiUrl)) return null;
    return 'No celular, use o IP do PC na rede Wi-Fi (ex.: '
        'http://192.168.0.10:${LanApiUrl.portaPadrao}). '
        'localhost e 127.0.0.1 so funcionam no proprio computador.';
  }

  /// Deve abrir a tela de configurar IP em vez de tentar conectar em loop.
  static bool deveRedirecionarParaConfiguracaoIp(String syncOuApiUrl) {
    final vazio = syncOuApiUrl.trim().isEmpty;
    if (vazio) return true;
    return validarUrlParaDispositivo(syncOuApiUrl) != null;
  }
}

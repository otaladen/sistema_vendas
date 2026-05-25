import 'dart:convert';
import 'dart:math';

/// Gera token aleatorio para autenticacao do sync LAN.
String gerarTokenSyncLan() {
  final r = Random.secure();
  final bytes = List<int>.generate(24, (_) => r.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

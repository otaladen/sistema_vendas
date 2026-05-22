import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Configura [HttpOverrides] para usar CAs confiaveis do sistema (Windows/Linux).
///
/// Corrige erros como `CERTIFICATE_VERIFY_FAILED` / `unable to get local issuer
/// certificate` em apps Flutter desktop.
void configurarHttpOverridesPlataforma() {
  if (!Platform.isWindows && !Platform.isLinux) return;
  HttpOverrides.global = _TrustedHttpOverrides();
}

class _TrustedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ctx = SecurityContext(withTrustedRoots: true);
    final client = HttpClient(context: ctx);
    client.connectionTimeout = const Duration(seconds: 30);
    client.idleTimeout = const Duration(seconds: 30);
    return client;
  }
}

/// Cliente HTTP com certificados raiz do sistema operacional.
http.Client createTrustedHttpClient() {
  final io = HttpClient(context: SecurityContext(withTrustedRoots: true));
  io.connectionTimeout = const Duration(seconds: 25);
  io.idleTimeout = const Duration(seconds: 25);
  return IOClient(io);
}

bool isFalhaSslHandshake(Object erro) {
  final texto = erro.toString().toLowerCase();
  return texto.contains('handshakeexception') ||
      texto.contains('certificate_verify_failed') ||
      texto.contains('unable to get local issuer certificate');
}

String mensagemErroSslAmigavel() {
  return 'Falha na conexao segura (HTTPS). Verifique data/hora do Windows, '
      'atualizacoes do sistema e se antivirus ou proxy nao intercepta o trafego.';
}

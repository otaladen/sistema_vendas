import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hash de senha com salt (compativel com sync JSON).
class UsuarioSenhaCodec {
  UsuarioSenhaCodec._();

  static const _prefixo = 'v1';

  static bool isHashArmazenado(String valor) {
    return valor.startsWith('$_prefixo\$');
  }

  static String gerarHash(String senhaPlain) {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = _digest(salt, senhaPlain);
    return '$_prefixo\$${base64Url.encode(salt)}\$${base64Url.encode(hash)}';
  }

  static bool verificar(String senhaPlain, String armazenado) {
    if (!isHashArmazenado(armazenado)) {
      return armazenado == senhaPlain;
    }
    final partes = armazenado.split('\$');
    if (partes.length != 3) return false;
    final salt = base64Url.decode(partes[1]);
    final esperado = base64Url.decode(partes[2]);
    final atual = _digest(salt, senhaPlain);
    if (atual.length != esperado.length) return false;
    var diff = 0;
    for (var i = 0; i < atual.length; i++) {
      diff |= atual[i] ^ esperado[i];
    }
    return diff == 0;
  }

  static List<int> _digest(List<int> salt, String senha) {
    final input = [...salt, ...utf8.encode(senha)];
    return sha256.convert(input).bytes;
  }
}

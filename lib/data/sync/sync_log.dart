import 'package:flutter/foundation.dart';

/// Ultimo resultado da sincronizacao periodica (diagnostico em Configuracoes).
class SyncLog {
  static final ValueNotifier<SyncLogEntry?> ultimo = ValueNotifier(null);

  static void registrarSucesso() {
    ultimo.value = SyncLogEntry(
      sucesso: true,
      mensagem: 'OK',
      em: DateTime.now(),
    );
    if (kDebugMode) {
      debugPrint('[sync] concluida com sucesso');
    }
  }

  static void registrarFalha(String mensagem) {
    final msg = mensagem.trim();
    if (msg.isEmpty) return;
    ultimo.value = SyncLogEntry(
      sucesso: false,
      mensagem: msg,
      em: DateTime.now(),
    );
    if (kDebugMode) {
      debugPrint('[sync] falha: $msg');
    }
  }
}

class SyncLogEntry {
  const SyncLogEntry({
    required this.sucesso,
    required this.mensagem,
    required this.em,
  });

  final bool sucesso;
  final String mensagem;
  final DateTime em;
}

import 'dart:io';

import '../data/backup_destino_resolver.dart';

/// Abre pastas no Explorer com validacao defensiva (evita `explorer \\`).
abstract final class WindowsShellPaths {
  WindowsShellPaths._();

  static Future<void> abrirPastaNoExplorador(String caminho) async {
    if (!Platform.isWindows) return;
    if (!BackupDestinoResolver.caminhoConfiguradoValido(caminho)) return;
    final dir = Directory(caminho.trim());
    if (!dir.existsSync()) return;
    await Process.start('explorer', [dir.path]);
  }
}

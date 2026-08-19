import 'package:shared_preferences/shared_preferences.dart';

/// Ultima copia de backup baixada neste terminal (sobrevive ao restart).
abstract final class BackupTerminalCopiaStorage {
  BackupTerminalCopiaStorage._();

  static const _kPath = 'backup_terminal_copia_path_v1';
  static const _kMs = 'backup_terminal_copia_ms_v1';
  static const _kBytes = 'backup_terminal_copia_bytes_v1';

  static Future<({String path, int ms, int bytes})> carregar() async {
    final p = await SharedPreferences.getInstance();
    return (
      path: p.getString(_kPath) ?? '',
      ms: p.getInt(_kMs) ?? 0,
      bytes: p.getInt(_kBytes) ?? 0,
    );
  }

  static Future<void> salvar({
    required String path,
    required int ms,
    required int bytes,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPath, path.trim());
    await p.setInt(_kMs, ms < 0 ? 0 : ms);
    await p.setInt(_kBytes, bytes < 0 ? 0 : bytes);
  }
}

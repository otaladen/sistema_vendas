import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_config_repository.dart';

/// Armazenamento da logomarca (servidor LAN e copia local por terminal).
abstract final class EmpresaLogoService {
  EmpresaLogoService._();

  /// Apenas testes: evita [path_provider] no ambiente de unit test.
  static Directory? pastaEmpresaOverrideForTest;

  static const nomeArquivoServidor = 'logo_loja.png';
  static const nomeArquivoTerminal = 'logo_loja_sync.png';

  static String hashBytes(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  static Future<String?> hashArquivo(String path) async {
    final f = File(path.trim());
    if (!f.existsSync()) return null;
    return hashBytes(await f.readAsBytes());
  }

  static Future<Directory> _pastaEmpresa() async {
    final override = pastaEmpresaOverrideForTest;
    if (override != null) {
      if (!override.existsSync()) {
        override.createSync(recursive: true);
      }
      return override;
    }
    final base = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'empresa'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<File> arquivoServidor() async {
    final dir = await _pastaEmpresa();
    return File(p.join(dir.path, nomeArquivoServidor));
  }

  static Future<File> arquivoTerminalLocal() async {
    final dir = await _pastaEmpresa();
    return File(p.join(dir.path, nomeArquivoTerminal));
  }

  static Future<Uint8List?> lerBytesServidor() async {
    final f = await arquivoServidor();
    if (!f.existsSync()) return null;
    final b = await f.readAsBytes();
    return b.isEmpty ? null : b;
  }

  static Future<({String path, String hash})> gravarServidor(
    Uint8List bytes,
  ) async {
    final f = await arquivoServidor();
    await f.writeAsBytes(bytes, flush: true);
    return (path: f.path, hash: hashBytes(bytes));
  }

  static Future<void> removerServidor() async {
    final f = await arquivoServidor();
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static Future<({String path, String hash})> gravarTerminalLocal(
    Uint8List bytes,
  ) async {
    final f = await arquivoTerminalLocal();
    await f.writeAsBytes(bytes, flush: true);
    return (path: f.path, hash: hashBytes(bytes));
  }

  static Future<void> removerTerminalLocal() async {
    final f = await arquivoTerminalLocal();
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static Future<Uint8List?> lerLogoEfetiva(EmpresaConfig config) async {
    final path = config.logoPath.trim();
    if (path.isNotEmpty) {
      final f = File(path);
      if (f.existsSync()) {
        final b = await f.readAsBytes();
        if (b.isNotEmpty) return b;
      }
    }
    return lerBytesServidor();
  }

  /// Copia arquivo escolhido pelo usuario para pasta padrao (antes do upload).
  static Future<String> importarDeArquivo(String sourcePath) async {
    final f = await arquivoServidor();
    await File(sourcePath).copy(f.path);
    return f.path;
  }
}

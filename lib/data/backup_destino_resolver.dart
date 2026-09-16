import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config_repository.dart';
import 'local_app_data_paths.dart';

/// Resolve e valida pastas de destino de backup (local, rede, fallback do app).
abstract final class BackupDestinoResolver {
  BackupDestinoResolver._();

  static const subpastaFallbackApp = 'backups_terminais';

  /// Rejeita vazio, so barras ou prefixo UNC incompleto (`\\` / `\\servidor` sem share).
  static bool caminhoConfiguradoValido(String? raw) {
    final pasta = (raw ?? '').trim();
    if (pasta.isEmpty) return false;
    if (pasta == r'\' || pasta == r'\\') return false;
    if (pasta.startsWith(r'\\')) {
      final resto = pasta.substring(2);
      if (resto.isEmpty) return false;
      final segmentos =
          resto.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();
      if (segmentos.length < 2) return false;
    }
    return true;
  }

  static Future<Directory> resolverPastaRaiz({
    required EmpresaConfig config,
    required BackupRegistroManual manual,
    String subpastaFallback = subpastaFallbackApp,
  }) async {
    var pasta = config.backupAutomaticoPasta.trim();
    if (!caminhoConfiguradoValido(pasta)) {
      pasta = manual.pastaPadrao.trim();
    }
    if (!caminhoConfiguradoValido(pasta)) {
      final base = await obterDiretorioBaseDadosApp();
      pasta = p.join(base.path, subpastaFallback);
    }
    final dir = Directory(pasta);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}

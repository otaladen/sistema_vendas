import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pastas de fotos POD (local e servidor LAN — fase 2).
abstract final class EntregaPodPaths {
  EntregaPodPaths._();

  static const subpastaLocal = 'pod_entrega';
  static const subpastaCache = 'pod_entrega_cache';

  /// Subpasta no PC servidor (ao lado do .exe / sync_server).
  static const subpastaServidor = 'pod_entrega';

  static Future<Directory> diretorioLocal() async {
    final base = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, subpastaLocal));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Pasta central no servidor para replicar fotos na rede (fase 2).
  static Directory? diretorioServidorSeExistir() {
    if (!Platform.isWindows) return null;
    try {
      final resolved = Platform.resolvedExecutable;
      if (resolved.isEmpty) return null;
      final dir = Directory(
        p.join(File(resolved).parent.path, subpastaServidor),
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> diretorioCache() async {
    final base = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, subpastaCache));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String nomeArquivoVenda(int vendaId) {
    final ts = DateTime.now().toUtc();
    final stamp =
        '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_'
        '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
    return 'venda_${vendaId}_$stamp.jpg';
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/entrega_pod_nome_arquivo.dart';

/// Pastas de fotos POD (local e servidor LAN — fase 2).
abstract final class EntregaPodPaths {
  EntregaPodPaths._();

  static const subpastaLocal = 'pod_entrega';
  static const subpastaCache = 'pod_entrega_cache';

  /// Subpasta no PC servidor (ao lado do .exe).
  static const subpastaServidor = 'pod_entrega';

  /// Camera/galeria no celular: pre-limite antes do JPEG final.
  static const pickerMaxWidth = 1280;
  static const pickerQuality = 72;

  /// JPEG gravado e enviado ao PC1.
  static const jpegMaxWidth = 960;
  static const jpegQuality = 70;

  static const maxBytesJpeg = 6 * 1024 * 1024;

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

  /// Grava JPEG na pasta do PC servidor e devolve o path relativo da venda.
  static Future<String> gravarJpegServidor({
    required String fileName,
    required List<int> bytes,
  }) async {
    if (!EntregaPodNomeArquivo.valido(fileName)) {
      throw StateError('nome de arquivo POD invalido');
    }
    if (bytes.isEmpty) {
      throw StateError('imagem vazia');
    }
    if (bytes.length > maxBytesJpeg) {
      throw StateError('arquivo muito grande');
    }
    final dir = diretorioServidorSeExistir();
    if (dir == null) {
      throw StateError('pasta de fotos POD indisponivel neste PC');
    }
    final file = File(p.normalize(p.join(dir.path, fileName)));
    final dirNorm = p.normalize(dir.absolute.path);
    if (!p.isWithin(dirNorm, p.normalize(file.absolute.path))) {
      throw StateError('caminho invalido');
    }
    await file.writeAsBytes(bytes, flush: true);
    return '$subpastaServidor/$fileName';
  }

  static File? arquivoServidorDe(String fileName) {
    if (!EntregaPodNomeArquivo.valido(fileName)) return null;
    final dir = diretorioServidorSeExistir();
    if (dir == null) return null;
    final file = File(p.normalize(p.join(dir.path, fileName)));
    final dirNorm = p.normalize(dir.absolute.path);
    if (!p.isWithin(dirNorm, p.normalize(file.absolute.path))) return null;
    return file;
  }

  static String nomeArquivoVenda(int vendaId) {
    final ts = DateTime.now().toUtc();
    final stamp =
        '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_'
        '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}${ts.second.toString().padLeft(2, '0')}';
    return 'venda_${vendaId}_$stamp.jpg';
  }
}

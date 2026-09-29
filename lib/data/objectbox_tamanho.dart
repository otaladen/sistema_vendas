import 'dart:io';

import 'package:path/path.dart' as p;

/// Leitura do arquivo LMDB sem abrir o [Store].
class ObjectBoxTamanho {
  ObjectBoxTamanho._();

  static const int bytesPorMegabyte = 1024 * 1024;

  static File arquivoDataMdb(String storeDirectoryPath) =>
      File(p.join(storeDirectoryPath, 'data.mdb'));

  /// Megabytes ocupados por `data.mdb` (base 1024). Zero se o arquivo nao existe.
  static double dataMdbEmMb(String storeDirectoryPath) {
    final arquivo = arquivoDataMdb(storeDirectoryPath);
    if (!arquivo.existsSync()) return 0;
    return arquivo.lengthSync() / bytesPorMegabyte;
  }
}

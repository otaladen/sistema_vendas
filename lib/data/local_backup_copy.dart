import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> copiarDiretorioRecursivo({
  required Directory origem,
  required Directory destino,
}) async {
  if (!origem.existsSync()) return;
  destino.createSync(recursive: true);
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      await copiarDiretorioRecursivo(
        origem: entidade,
        destino: Directory(destinoPath),
      );
    } else if (entidade is File) {
      await entidade.copy(destinoPath);
    }
  }
}

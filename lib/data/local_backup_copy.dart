import 'dart:io';

import 'package:path/path.dart' as p;

Future<int> contarArquivosRecursivo(Directory origem) async {
  if (!origem.existsSync()) return 0;
  var n = 0;
  await for (final entidade in origem.list(recursive: true)) {
    if (entidade is File) n++;
  }
  return n;
}

Future<void> copiarDiretorioRecursivo({
  required Directory origem,
  required Directory destino,
  void Function()? onArquivoCopiado,
}) async {
  if (!origem.existsSync()) return;
  destino.createSync(recursive: true);
  var n = 0;
  await for (final entidade in origem.list(recursive: false)) {
    final nome = p.basename(entidade.path);
    final destinoPath = p.join(destino.path, nome);
    if (entidade is Directory) {
      await copiarDiretorioRecursivo(
        origem: entidade,
        destino: Directory(destinoPath),
        onArquivoCopiado: onArquivoCopiado,
      );
    } else if (entidade is File) {
      await entidade.copy(destinoPath);
      onArquivoCopiado?.call();
      n++;
      // Libera o UI periodicamente em pastas grandes.
      if (n % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
}

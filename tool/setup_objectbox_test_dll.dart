// Substitui `dart run objectbox_flutter_libs:setup` (removido no objectbox 5.x).
//
// Copia objectbox.dll do build Windows para lib/, onde testes Dart/Flutter carregam a lib nativa.
import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  if (!Platform.isWindows) {
    stdout.writeln('setup_objectbox_test_dll: ignorado (nao e Windows).');
    exit(0);
  }

  final root = Directory.current.path;
  final destDir = Directory(p.join(root, 'lib'));
  final destDll = File(p.join(destDir.path, 'objectbox.dll'));

  final candidates = [
    p.join(root, 'build', 'windows', 'x64', '_deps', 'objectbox-download-src', 'lib'),
    p.join(root, 'build', 'windows', 'x64', 'runner', 'Debug'),
    p.join(root, 'build', 'windows', 'x64', 'runner', 'Release'),
  ];

  for (final dir in candidates) {
    final src = File(p.join(dir, 'objectbox.dll'));
    if (src.existsSync()) {
      destDir.createSync(recursive: true);
      src.copySync(destDll.path);
      stdout.writeln('objectbox.dll copiado para ${destDll.path}');
      exit(0);
    }
  }

  stderr.writeln(
    'objectbox.dll nao encontrada. Execute antes: flutter build windows',
  );
  exit(1);
}

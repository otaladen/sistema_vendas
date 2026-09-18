import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/objectbox.dart' as app;

/// Garante [objectbox.dll] em `lib/` (caminho que o pacote objectbox usa no Windows).
///
/// Retorna mensagem de skip quando a DLL nao puder ser carregada — rode
/// `flutter build windows` (ou copie manualmente) antes dos testes de integracao.
String? prepararObjectBoxDllParaTestes() {
  if (!Platform.isWindows) {
    return null;
  }

  final root = Directory.current.path;
  final destDir = Directory(p.join(root, 'lib'));
  final destDll = File(p.join(destDir.path, 'objectbox.dll'));

  if (!destDll.existsSync()) {
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
        break;
      }
    }
  }

  Directory? probeDir;
  try {
    probeDir = Directory.systemTemp.createTempSync('sv_obx_probe_');
    final probe = app.ObjectBox.createForTest(probeDir);
    probe.close();
    return null;
  } catch (e) {
    return 'objectbox.dll indisponivel neste ambiente — '
        'rode flutter build windows ou dart run tool/setup_objectbox_test_dll.dart '
        '($e)';
  } finally {
    try {
      probeDir?.deleteSync(recursive: true);
    } catch (_) {}
  }
}

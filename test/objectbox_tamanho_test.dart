import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/objectbox_tamanho.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sv_obx_tamanho_');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('data.mdb ausente mede zero', () {
    expect(ObjectBoxTamanho.dataMdbEmMb(temp.path), 0);
  });

  test('data.mdb de 1,5 MB', () {
    final arquivo = File(p.join(temp.path, 'data.mdb'));
    arquivo.writeAsBytesSync(List<int>.filled(1536 * 1024, 1));

    expect(ObjectBoxTamanho.dataMdbEmMb(temp.path), closeTo(1.5, 0.001));
  });
}

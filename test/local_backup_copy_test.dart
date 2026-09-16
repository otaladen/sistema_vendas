import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/local_backup_copy.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sv_backup_copy_');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('copia e contagem ignoram a pasta logs', () async {
    final origem = Directory(p.join(temp.path, 'origem'))..createSync();
    File(p.join(origem.path, 'data.txt')).writeAsStringSync('ok');
    final logs = Directory(p.join(origem.path, 'logs'))..createSync();
    File(p.join(logs.path, 'boot_diagnostico.log')).writeAsStringSync('log');

    expect(await contarArquivosRecursivo(origem), 1);

    final destino = Directory(p.join(temp.path, 'destino'));
    await copiarDiretorioRecursivo(origem: origem, destino: destino);

    expect(File(p.join(destino.path, 'data.txt')).existsSync(), isTrue);
    expect(Directory(p.join(destino.path, 'logs')).existsSync(), isFalse);
  });

  test('limpeza da restauracao preserva logs e apaga o restante', () async {
    final base = Directory(p.join(temp.path, 'appdata'))..createSync();
    Directory(p.join(base.path, 'objectbox')).createSync();
    File(p.join(base.path, 'objectbox', 'data.mdb')).writeAsStringSync('mdb');
    final logs = Directory(p.join(base.path, 'logs'))..createSync();
    File(p.join(logs.path, 'boot_diagnostico.log')).writeAsStringSync('log');

    await limparDiretorioDestinoRestauracao(base);

    expect(Directory(p.join(base.path, 'objectbox')).existsSync(), isFalse);
    expect(Directory(p.join(base.path, 'logs')).existsSync(), isTrue);
    expect(
      File(p.join(base.path, 'logs', 'boot_diagnostico.log')).existsSync(),
      isTrue,
    );
  });
}

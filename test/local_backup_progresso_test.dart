import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/local_backup_copy.dart';
import 'package:sistema_vendas/data/local_backup_isolate.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sv_backup_prog_');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('copiarObjectBoxSomenteBanco emite progresso de 0% a 100%', () async {
    final origem = Directory(p.join(temp.path, 'objectbox'))..createSync();
    final mdb = File(p.join(origem.path, 'data.mdb'));
    final payload = List<int>.filled(256 * 1024, 7);
    await mdb.writeAsBytes(payload, flush: true);
    File(p.join(origem.path, 'data.mdb-lock')).writeAsStringSync('lock');

    final destino = Directory(p.join(temp.path, 'destino_ob'));
    final marcos = <double>[];
    await copiarObjectBoxSomenteBanco(
      origem: origem,
      destino: destino,
      onProgressoBytes: (copiados, total) {
        if (total <= 0) return;
        marcos.add(copiados / total);
      },
    );

    expect(await File(p.join(destino.path, 'data.mdb')).length(), payload.length);
    expect(File(p.join(destino.path, 'data.mdb-lock')).existsSync(), isFalse);
    expect(marcos, isNotEmpty);
    expect(marcos.last, closeTo(1.0, 0.001));
    expect(marcos.first, greaterThan(0));
  });

  test('executarCopiaLocalBackupIsolate conclui rapido e notifica progresso',
      () async {
    final origem = Directory(p.join(temp.path, 'objectbox'))..createSync();
    await File(p.join(origem.path, 'data.mdb')).writeAsBytes(
      List<int>.filled(64 * 1024, 3),
      flush: true,
    );
    final destino = Directory(p.join(temp.path, 'copia_isolate'));

    final inicio = DateTime.now();
    final eventos = <List<dynamic>>[];
    final resultado = await executarCopiaLocalBackupIsolate(
      somenteBanco: true,
      origem: origem,
      destino: destino,
      onProgress: (progresso, etapa) {
        eventos.add([progresso, etapa]);
      },
    );
    final duracao = DateTime.now().difference(inicio);

    expect(resultado.checksumDataMdbSha256, isNotNull);
    expect(File(p.join(destino.path, 'data.mdb')).existsSync(), isTrue);
    expect(eventos, isNotEmpty);
    final maiorProgresso = eventos
        .map((e) => (e[0] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    expect(maiorProgresso, greaterThanOrEqualTo(0.75));
    expect(
      eventos.any((e) => (e[1] as String).contains('banco')),
      isTrue,
    );
    expect(duracao.inMinutes, lessThan(1));
  });
}

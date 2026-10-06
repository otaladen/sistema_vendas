import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/local_backup_copy.dart';
import 'package:sistema_vendas/data/local_backup_isolate.dart';
import 'package:sistema_vendas/data/local_backup_validation.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sv_backup_opcionais_');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  Future<Directory> _montarDadosApp({required bool incluirListasPrecoExternas}) async {
    final base = Directory(p.join(temp.path, 'dados_app'))..createSync();
    final ob = Directory(p.join(base.path, 'objectbox'))..createSync();
    await File(p.join(ob.path, 'data.mdb')).writeAsBytes(
      List<int>.filled(32 * 1024, 1),
      flush: true,
    );
    if (incluirListasPrecoExternas) {
      final listas = Directory(p.join(base.path, 'listas_preco_externas'))
        ..createSync();
      await File(p.join(listas.path, 'index.json')).writeAsString('[]');
    }
    return base;
  }

  test('copia conclui sem pasta opcional listas_preco_externas', () async {
    final origem = await _montarDadosApp(incluirListasPrecoExternas: false);
    final destino = Directory(p.join(temp.path, 'dados_aplicacao'));

    await copiarDiretorioRecursivo(origem: origem, destino: destino);

    expect(LocalBackupValidation.localizarDataMdb(destino), isNotNull);
    expect(
      Directory(p.join(destino.path, 'listas_preco_externas')).existsSync(),
      isFalse,
    );
  });

  test('copia pasta opcional com index.json cria subpasta no destino', () async {
    final origem = await _montarDadosApp(incluirListasPrecoExternas: true);
    final destino = Directory(p.join(temp.path, 'dest_com_listas'));

    await copiarDiretorioRecursivo(origem: origem, destino: destino);

    final index = File(
      p.join(destino.path, 'listas_preco_externas', 'index.json'),
    );
    expect(index.existsSync(), isTrue);
    expect(await index.readAsString(), '[]');
  });

  test('isolate de backup conclui sem subpastas opcionais', () async {
    final origem = await _montarDadosApp(incluirListasPrecoExternas: false);
    final destino = Directory(p.join(temp.path, 'dest_isolate'));

    final resultado = await executarCopiaLocalBackupIsolate(
      somenteBanco: false,
      origem: origem,
      destino: destino,
    );

    expect(resultado.checksumDataMdbSha256, isNotNull);
    expect(LocalBackupValidation.localizarDataMdb(destino), isNotNull);
    expect(
      Directory(p.join(destino.path, 'listas_preco_externas')).existsSync(),
      isFalse,
    );
  });
}

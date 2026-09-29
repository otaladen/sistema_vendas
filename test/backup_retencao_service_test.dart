import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistema_vendas/data/backup_retencao_service.dart';
import 'package:sistema_vendas/domain/backup_retencao.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sv_backup_retencao_');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  test('normaliza retencao de completos para 2, 4 ou 8', () {
    expect(BackupRetencaoCompletosOpcoes.normalizar(null), 4);
    expect(BackupRetencaoCompletosOpcoes.normalizar(1), 2);
    expect(BackupRetencaoCompletosOpcoes.normalizar(5), 4);
    expect(BackupRetencaoCompletosOpcoes.normalizar(0), 0);
  });

  test('leve e completo nao disputam o mesmo limite', () async {
    for (var dia = 1; dia <= 8; dia++) {
      final stamp = '202601${dia.toString().padLeft(2, '0')}_100000';
      await _gravar(
        temp,
        stamp,
        dia.isEven ? 'sem_imagens' : 'somente_banco',
      );
    }
    await _gravar(temp, '20260101_120000', 'completo');
    await _gravar(temp, '20260102_120000', 'completo');
    await _gravar(temp, '20260103_120000', 'completo');
    await _gravar(temp, '20260104_120000', 'cadastro_produtos');

    final removidos = await BackupRetencaoService.aplicar(
      pastaRaiz: temp,
      maxCopiasLeves: 7,
      maxCopiasCompletos: 2,
    );

    expect(removidos, 2);
    expect(_existe(temp, '20260101_100000'), isFalse);
    expect(_existe(temp, '20260102_100000'), isTrue);
    expect(_existe(temp, '20260108_100000'), isTrue);
    expect(_existe(temp, '20260103_120000'), isTrue);
    expect(_existe(temp, '20260102_120000'), isTrue);
    expect(_existe(temp, '20260101_120000'), isFalse);
    expect(_existe(temp, '20260104_120000'), isTrue);
  });
}

Future<void> _gravar(Directory raiz, String stamp, String escopo) async {
  final pasta = Directory(p.join(raiz.path, 'backup_sistema_vendas_$stamp'))
    ..createSync();
  final dados = Directory(p.join(pasta.path, 'dados_aplicacao', 'objectbox'))
    ..createSync(recursive: true);
  File(p.join(dados.path, 'data.mdb')).writeAsStringSync('x' * 5000);
  await File(p.join(pasta.path, 'manifest.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'escopo': escopo,
      'criadoEm': _iso(stamp),
      'tipo': 'automatico',
      'tamanhoBancoKb': 5,
      'tamanhoPastaKb': 8,
      'pastaDados': 'dados_aplicacao',
    }),
  );
}

String _iso(String stamp) {
  final ano = stamp.substring(0, 4);
  final mes = stamp.substring(4, 6);
  final dia = stamp.substring(6, 8);
  final hora = stamp.substring(9, 11);
  final min = stamp.substring(11, 13);
  final seg = stamp.substring(13, 15);
  return '$ano-$mes-${dia}T$hora:$min:$seg';
}

bool _existe(Directory raiz, String stamp) {
  return Directory(p.join(raiz.path, 'backup_sistema_vendas_$stamp')).existsSync();
}

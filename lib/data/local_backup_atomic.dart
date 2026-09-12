import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'local_backup_service.dart';
import 'local_backup_validation.dart';

/// Gravacao atomica de pastas `backup_sistema_vendas_*` (`.tmp` → rename).
abstract final class LocalBackupAtomic {
  LocalBackupAtomic._();

  static const suffixTmp = '.tmp';

  static String nomePastaFinal(String timestamp) =>
      'backup_sistema_vendas_$timestamp';

  static Directory pastaTemp(Directory destinoRaiz, String timestamp) =>
      Directory(
        p.join(
          destinoRaiz.path,
          '${nomePastaFinal(timestamp)}$suffixTmp',
        ),
      );

  static Directory pastaFinal(Directory destinoRaiz, String timestamp) =>
      Directory(p.join(destinoRaiz.path, nomePastaFinal(timestamp)));

  static void removerPastaTempSeExistir(Directory pastaTemp) {
    if (pastaTemp.existsSync()) {
      pastaTemp.deleteSync(recursive: true);
    }
  }

  /// Valida conteudo e renomeia `.tmp` para o nome definitivo.
  static Future<Directory> promoverPastaTemp({
    required Directory pastaTemp,
    required Directory pastaFinal,
    required Directory dadosValidacao,
    required LocalBackupEscopo escopo,
  }) async {
    if (!pastaTemp.existsSync()) {
      throw Exception('Pasta temporaria de backup nao encontrada.');
    }
    if (escopo == LocalBackupEscopo.cadastroProdutos) {
      LocalBackupValidation.validarCadastroProdutos(pastaTemp);
    } else {
      LocalBackupValidation.validarDadosAplicacao(dadosValidacao);
      validarChecksumManifesto(pastaTemp);
    }
    if (pastaFinal.existsSync()) {
      pastaFinal.deleteSync(recursive: true);
    }
    try {
      pastaTemp.renameSync(pastaFinal.path);
    } on FileSystemException {
      await _promoverCopiando(pastaTemp, pastaFinal);
      pastaTemp.deleteSync(recursive: true);
    }
    return pastaFinal;
  }

  static void validarChecksumManifesto(Directory pastaBackup) {
    final manifestFile =
        File(p.join(pastaBackup.path, LocalBackupService.manifestFileName));
    if (!manifestFile.existsSync()) {
      throw LocalBackupInvalidoException(
        'Manifesto do backup ausente antes de concluir a copia.',
      );
    }
    final map =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final checksum = map['checksumDataMdbSha256'];
    if (checksum is! String || checksum.isEmpty) {
      throw LocalBackupInvalidoException(
        'Checksum do backup invalido no manifesto.',
      );
    }
    final pastaDados = map['pastaDados'];
    if (pastaDados is! String) return;
    final dadosDir = Directory(p.join(pastaBackup.path, pastaDados));
    final mdb = LocalBackupValidation.localizarDataMdb(dadosDir);
    if (mdb == null) return;
    final digest = sha256.convert(mdb.readAsBytesSync()).toString();
    if (digest != checksum) {
      throw LocalBackupInvalidoException(
        'Checksum do data.mdb nao confere apos a copia (arquivo incompleto).',
      );
    }
  }

  static String checksumDataMdb(Directory dadosAplicacao) {
    final mdb = LocalBackupValidation.localizarDataMdb(dadosAplicacao);
    if (mdb == null) {
      throw LocalBackupInvalidoException(
        'data.mdb ausente para calcular checksum do backup.',
      );
    }
    return sha256.convert(mdb.readAsBytesSync()).toString();
  }

  static Future<void> _promoverCopiando(
    Directory origem,
    Directory destino,
  ) async {
    destino.createSync(recursive: true);
    await for (final ent in origem.list(recursive: true)) {
      final rel = p.relative(ent.path, from: origem.path);
      final out = p.join(destino.path, rel);
      if (ent is Directory) {
        Directory(out).createSync(recursive: true);
      } else if (ent is File) {
        await ent.copy(out);
      }
    }
  }
}

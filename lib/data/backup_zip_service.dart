import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../domain/auditoria_catalogo.dart';
import '../services/auditoria_registrar.dart';
import 'local_backup_validation.dart';

class BackupZipResultado {
  const BackupZipResultado({
    required this.arquivo,
    required this.criptografado,
  });

  final File arquivo;
  final bool criptografado;
}

/// Compacta pasta de backup em ZIP; senha opcional gera `.zip.cript` (AES-256-CBC).
class BackupZipService {
  BackupZipService._();

  static const _magicCript = 'SVBK1';

  static Future<BackupZipResultado> exportarPasta({
    required Directory pastaBackup,
    String? senha,
    String? pastaDestinoArquivo,
    void Function(double progresso, String etapa)? onProgress,
  }) async {
    void report(double v, String etapa) => onProgress?.call(v, etapa);

    if (!pastaBackup.existsSync()) {
      throw Exception('Pasta de backup nao encontrada.');
    }
    LocalBackupValidation.resolverPastaDadosBackup(pastaBackup);

    report(0.1, 'Compactando…');
    final nomeBase = p.basename(pastaBackup.path);
    final destinoDir = pastaDestinoArquivo?.trim().isNotEmpty == true
        ? Directory(pastaDestinoArquivo!.trim())
        : pastaBackup.parent;
    if (!destinoDir.existsSync()) {
      destinoDir.createSync(recursive: true);
    }

    final zipPath = p.join(destinoDir.path, '$nomeBase.zip');
    final zipPathTmp = '$zipPath.tmp';
    final zipFileTmp = File(zipPathTmp);
    final zipFile = File(zipPath);
    if (zipFileTmp.existsSync()) {
      await zipFileTmp.delete();
    }
    if (zipFile.existsSync()) {
      await zipFile.delete();
    }

    try {
      final encoder = ZipFileEncoder();
      encoder.create(zipPathTmp);
      encoder.addDirectorySync(pastaBackup);
      encoder.closeSync();

      final bytes = await zipFileTmp.length();
      if (bytes <= 0) {
        throw Exception('Arquivo ZIP temporario vazio apos compactacao.');
      }
      await zipFileTmp.rename(zipPath);
    } catch (e) {
      if (zipFileTmp.existsSync()) {
        await zipFileTmp.delete();
      }
      rethrow;
    }

    report(0.75, 'Finalizando arquivo…');
    final senhaLimpa = senha?.trim() ?? '';
    if (senhaLimpa.isEmpty) {
      report(1.0, 'ZIP criado');
      return BackupZipResultado(arquivo: zipFile, criptografado: false);
    }

    report(0.85, 'Criptografando com senha…');
    final zipBytes = await zipFile.readAsBytes();
    final criptPath = '$zipPath.cript';
    final criptFile = File(criptPath);
    await criptFile.writeAsBytes(
      _criptografarBytes(zipBytes, senhaLimpa),
    );
    await zipFile.delete();

    report(1.0, 'ZIP protegido criado');
    return BackupZipResultado(arquivo: criptFile, criptografado: true);
  }

  static Future<Directory> extrairParaRestauracao({
    required File arquivo,
    required Directory pastaTemp,
    String? senha,
  }) async {
    if (!pastaTemp.existsSync()) {
      pastaTemp.createSync(recursive: true);
    }

    Uint8List zipBytes;
    final nome = arquivo.path.toLowerCase();
    if (nome.endsWith('.cript')) {
      final senhaLimpa = senha?.trim() ?? '';
      if (senhaLimpa.isEmpty) {
        throw Exception('Informe a senha do arquivo .cript');
      }
      zipBytes = _descriptografarBytes(await arquivo.readAsBytes(), senhaLimpa);
    } else {
      zipBytes = await arquivo.readAsBytes();
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      final outPath = p.join(pastaTemp.path, file.name);
      if (file.isFile) {
        final outFile = File(outPath);
        outFile.createSync(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }

    return pastaTemp;
  }

  static Uint8List _criptografarBytes(Uint8List dados, String senha) {
    final salt = _bytesAleatorios(16);
    final iv = _bytesAleatorios(16);
    final key = _derivarChave(senha, salt);
    final cipherBytes = _aesCbcPkcs7(dados, key, iv, encrypt: true);

    final header = utf8.encode(_magicCript);
    return Uint8List.fromList([
      ...header,
      ...salt,
      ...iv,
      ...cipherBytes,
    ]);
  }

  static Uint8List _descriptografarBytes(Uint8List payload, String senha) {
    final magicLen = utf8.encode(_magicCript).length;
    if (payload.length < magicLen + 32) {
      throw Exception('Arquivo criptografado invalido.');
    }
    final magic = utf8.decode(payload.sublist(0, magicLen));
    if (magic != _magicCript) {
      throw Exception('Formato de arquivo nao reconhecido.');
    }
    final salt = payload.sublist(magicLen, magicLen + 16);
    final iv = payload.sublist(magicLen + 16, magicLen + 32);
    final cipher = payload.sublist(magicLen + 32);
    final key = _derivarChave(senha, salt);
    try {
      return _aesCbcPkcs7(cipher, key, iv, encrypt: false);
    } catch (_) {
      throw Exception('Senha incorreta ou arquivo corrompido.');
    }
  }

  static Uint8List _derivarChave(String senha, List<int> salt) {
    var block = Uint8List.fromList(utf8.encode(senha));
    for (var i = 0; i < 12000; i++) {
      block = Uint8List.fromList(sha256.convert([...block, ...salt]).bytes);
    }
    return Uint8List.fromList(block.sublist(0, 32));
  }

  static Uint8List _aesCbcPkcs7(
    Uint8List input,
    Uint8List key,
    Uint8List iv, {
    required bool encrypt,
  }) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        encrypt,
        ParametersWithIV(KeyParameter(key), iv),
      );
    final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
    padded.init(
      encrypt,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );
    return padded.process(input);
  }

  static Uint8List _bytesAleatorios(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rnd.nextInt(256)),
    );
  }

  static void registrarExportacao(BackupZipResultado resultado) {
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.backup,
      acao: AuditoriaAcao.backupZipExport,
      resumo: resultado.criptografado
          ? 'Backup exportado em ZIP protegido'
          : 'Backup exportado em ZIP',
      detalhes: {
        'arquivo': resultado.arquivo.path,
        'criptografado': resultado.criptografado,
      },
    );
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_backup_copy.dart';
import 'local_backup_validation.dart';

/// Restaura dados locais no diretorio padrao do app ([destinoBase]).
Future<void> restaurarDadosLocais({
  required Directory pastaBackupSelecionada,
  required Directory destinoBase,
  required Future<void> Function(Directory destino) limparDestino,
}) async {
  final origemDados = LocalBackupValidation.resolverPastaDadosBackup(
    pastaBackupSelecionada,
  );
  LocalBackupValidation.validarDadosAplicacao(origemDados);

  if (LocalBackupValidation.ehPastaObjectBox(origemDados)) {
    final destinoOb = Directory(p.join(destinoBase.path, 'objectbox'));
    if (destinoOb.existsSync()) {
      await destinoOb.delete(recursive: true);
    }
    destinoOb.createSync(recursive: true);
    await copiarDiretorioRecursivo(origem: origemDados, destino: destinoOb);
  } else {
    await limparDestino(destinoBase);
    await copiarDiretorioRecursivo(origem: origemDados, destino: destinoBase);
  }

  LocalBackupValidation.validarDadosAplicacao(destinoBase);
}

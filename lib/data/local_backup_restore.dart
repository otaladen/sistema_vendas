import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_backup_cadastro_produtos_service.dart';
import 'local_backup_copy.dart';
import 'local_backup_preferencias_service.dart';
import 'local_backup_service.dart';
import 'local_backup_validation.dart';
import 'objectbox.dart';

/// Restaura dados locais no diretorio padrao do app ([destinoBase]).
Future<CadastroProdutosImportResumo?> restaurarDadosLocais({
  required Directory pastaBackupSelecionada,
  required Directory destinoBase,
  required Future<void> Function(Directory destino) limparDestino,
  ObjectBox? objectBox,
}) async {
  final escopo = await LocalBackupService.lerEscopoManifest(
    pastaBackupSelecionada,
  );

  if (escopo == LocalBackupEscopo.cadastroProdutos) {
    if (objectBox == null) {
      throw Exception(
        'Restauracao de cadastro de produtos requer banco aberto.',
      );
    }
    LocalBackupValidation.validarCadastroProdutos(pastaBackupSelecionada);
    return LocalBackupCadastroProdutosService.importar(
      objectBox: objectBox,
      pastaBackup: pastaBackupSelecionada,
    );
  }

  final origemDados = LocalBackupValidation.resolverPastaDadosBackup(
    pastaBackupSelecionada,
  );
  LocalBackupValidation.validarDadosAplicacao(origemDados);

  if (escopo == LocalBackupEscopo.somenteBanco) {
    final origemOb = LocalBackupValidation.ehPastaObjectBox(origemDados)
        ? origemDados
        : Directory(p.join(origemDados.path, 'objectbox'));
    if (!origemOb.existsSync()) {
      throw LocalBackupInvalidoException(
        'Backup somente banco invalido: pasta objectbox ausente.',
      );
    }
    final destinoOb = Directory(p.join(destinoBase.path, 'objectbox'));
    if (destinoOb.existsSync()) {
      await destinoOb.delete(recursive: true);
    }
    destinoOb.createSync(recursive: true);
    await copiarDiretorioRecursivo(origem: origemOb, destino: destinoOb);
    LocalBackupValidation.validarDadosAplicacao(destinoBase);
    return null;
  }

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

  if (LocalBackupPreferenciasService.existeNaPasta(pastaBackupSelecionada)) {
    await LocalBackupPreferenciasService.importarDaPasta(
      pastaBackupSelecionada,
    );
  }
  return null;
}

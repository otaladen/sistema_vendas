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
  void Function(double progresso, String etapa)? onProgress,
}) async {
  void report(double v, String etapa) => onProgress?.call(v.clamp(0, 1), etapa);

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
      onProgress: onProgress,
    );
  }

  final origemDados = LocalBackupValidation.resolverPastaDadosBackup(
    pastaBackupSelecionada,
  );
  LocalBackupValidation.validarDadosAplicacao(origemDados);

  Future<void> copiarComProgresso({
    required Directory origem,
    required Directory destino,
    required double inicio,
    required double fim,
    required String rotulo,
  }) async {
    report(inicio, '$rotulo… ${(inicio * 100).round()}%');
    final total = await contarArquivosRecursivo(origem);
    var copiados = 0;
    await copiarDiretorioRecursivo(
      origem: origem,
      destino: destino,
      onArquivoCopiado: () {
        copiados++;
        if (total <= 0) return;
        final frac = copiados / total;
        final v = inicio + (fim - inicio) * frac;
        final pct = (v * 100).round().clamp(0, 99);
        if (copiados == 1 ||
            copiados == total ||
            copiados % 5 == 0) {
          report(v, '$rotulo… $pct%  ($copiados/$total)');
        }
      },
    );
    report(fim, '$rotulo concluido — ${(fim * 100).round()}%');
  }

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
    await copiarComProgresso(
      origem: origemOb,
      destino: destinoOb,
      inicio: 0.2,
      fim: 0.92,
      rotulo: 'Copiando banco',
    );
    LocalBackupValidation.validarDadosAplicacao(destinoBase);
    report(1.0, 'Restauracao concluida — 100%');
    return null;
  }

  if (LocalBackupValidation.ehPastaObjectBox(origemDados)) {
    final destinoOb = Directory(p.join(destinoBase.path, 'objectbox'));
    if (destinoOb.existsSync()) {
      await destinoOb.delete(recursive: true);
    }
    destinoOb.createSync(recursive: true);
    await copiarComProgresso(
      origem: origemDados,
      destino: destinoOb,
      inicio: 0.2,
      fim: 0.92,
      rotulo: 'Copiando banco',
    );
  } else {
    report(0.12, 'Limpando pasta atual… 12%');
    await limparDestino(destinoBase);
    await copiarComProgresso(
      origem: origemDados,
      destino: destinoBase,
      inicio: 0.18,
      fim: 0.88,
      rotulo: 'Restaurando arquivos',
    );
  }

  LocalBackupValidation.validarDadosAplicacao(destinoBase);

  if (LocalBackupPreferenciasService.existeNaPasta(pastaBackupSelecionada)) {
    report(0.92, 'Importando configuracoes… 92%');
    await LocalBackupPreferenciasService.importarDaPasta(
      pastaBackupSelecionada,
    );
  }
  report(1.0, 'Restauracao concluida — 100%');
  return null;
}

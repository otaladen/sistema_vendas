import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../data/objectbox.dart';
import 'local_app_data_paths.dart';
import 'local_backup_copy.dart';
import 'local_backup_validation.dart';
import 'sync/lan_sync_scheduler.dart';

enum LocalBackupTipo { manual, automatico }

typedef BackupProgressCallback = void Function(double progresso, String etapa);

class LocalBackupResult {
  const LocalBackupResult({
    required this.pastaBackup,
    required this.pastaDados,
    required this.tamanhoBancoKb,
    required this.criadoEm,
  });

  final Directory pastaBackup;
  final Directory pastaDados;
  final double tamanhoBancoKb;
  final DateTime criadoEm;
}

/// Copia completa dos dados locais com manifesto e progresso.
class LocalBackupService {
  LocalBackupService._();

  static const String manifestFileName = 'manifest.json';
  static const String versaoApp = '1.0.0';

  static Future<LocalBackupResult> executar({
    required Directory destinoRaiz,
    required LocalBackupTipo tipo,
    required String nomeLoja,
    required ObjectBox objectBox,
    LanSyncScheduler? lanSyncScheduler,
    BackupProgressCallback? onProgress,
  }) async {
    void report(double v, String etapa) => onProgress?.call(v, etapa);

    report(0.02, 'Validando dados locais…');
    final baseDadosDir = await obterDiretorioBaseDadosApp();
    if (!baseDadosDir.existsSync()) {
      throw Exception('Pasta de dados local nao encontrada.');
    }
    LocalBackupValidation.validarDadosAplicacao(baseDadosDir);

    final agora = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(agora);
    final pastaBackup = Directory(
      p.join(destinoRaiz.path, 'backup_sistema_vendas_$timestamp'),
    );
    pastaBackup.createSync(recursive: true);
    final destinoDados = Directory(
      p.join(pastaBackup.path, 'dados_aplicacao'),
    );

    report(0.12, 'Preparando copia…');
    var syncParada = false;
    if (lanSyncScheduler != null && lanSyncScheduler.estaAgendado) {
      await lanSyncScheduler.parar();
      syncParada = true;
    }
    await objectBox.fecharParaCopiaDeArquivos();
    try {
      report(0.18, 'Contando arquivos…');
      final totalArquivos = await contarArquivosRecursivo(baseDadosDir);
      report(0.22, 'Copiando dados…');
      var copiados = 0;
      await copiarDiretorioRecursivo(
        origem: baseDadosDir,
        destino: destinoDados,
        onArquivoCopiado: totalArquivos > 0
            ? () {
                copiados++;
                final frac = copiados / totalArquivos;
                report(0.22 + frac * 0.62, 'Copiando… ($copiados/$totalArquivos)');
              }
            : null,
      );

      report(0.88, 'Verificando integridade…');
      LocalBackupValidation.validarDadosAplicacao(destinoDados);

      final mdb = LocalBackupValidation.localizarDataMdb(destinoDados);
      final tamanhoKb = mdb == null ? 0.0 : mdb.lengthSync() / 1024.0;

      report(0.94, 'Gravando manifesto…');
      final manifest = {
        'app': 'sistema_vendas',
        'versaoApp': versaoApp,
        'empresa': nomeLoja,
        'tipo': tipo.name,
        'criadoEm': agora.toIso8601String(),
        'tamanhoBancoKb': double.parse(tamanhoKb.toStringAsFixed(2)),
        'pastaDados': 'dados_aplicacao',
      };
      await File(p.join(pastaBackup.path, manifestFileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );

      report(1.0, 'Concluido');
      return LocalBackupResult(
        pastaBackup: pastaBackup,
        pastaDados: destinoDados,
        tamanhoBancoKb: tamanhoKb,
        criadoEm: agora,
      );
    } finally {
      try {
        await objectBox.reabrirAposCopiaDeArquivos();
      } catch (_) {}
      if (syncParada && lanSyncScheduler != null) {
        try {
          await lanSyncScheduler.iniciar();
        } catch (_) {}
      }
    }
  }
}

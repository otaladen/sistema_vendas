import 'dart:io';

import 'app_config_repository.dart';
import 'auto_backup_service.dart';
import 'backup_pos_execucao_service.dart';
import 'local_backup_service.dart';
import 'objectbox.dart';

/// Backup silencioso invocado pela tarefa agendada do Windows (`--backup-agendado`).
class BackupAgendadoHeadlessService {
  BackupAgendadoHeadlessService._();

  static const argBackupAgendado = '--backup-agendado';

  static bool deveExecutar(List<String> args) =>
      args.contains(argBackupAgendado);

  /// Retorna codigo de saida do processo (0 = ok).
  static Future<int> executar() async {
    if (AutoBackupService.emExecucao) return 3;

    ObjectBox? objectBox;
    try {
      objectBox = await ObjectBox.create();
    } catch (_) {
      return 4;
    }

    final repository = AppConfigRepository();
    try {
      final config = await repository.carregarEmpresaConfig();
      var pasta = config.backupAutomaticoPasta.trim();
      if (pasta.isEmpty) {
        final manual = await repository.carregarRegistroBackupManual();
        pasta = manual.pastaPadrao.trim();
      }
      if (pasta.isEmpty) return 2;

      final destino = Directory(pasta);
      if (!destino.existsSync()) return 5;

      final escopo = await repository.carregarBackupAutomaticoEscopo();
      final resultado = await LocalBackupService.executar(
        destinoRaiz: destino,
        tipo: LocalBackupTipo.automatico,
        nomeLoja: config.nomeLoja,
        objectBox: objectBox,
        escopo: escopo,
      );

      await BackupPosExecucaoService.aposBackupSucesso(
        repository: repository,
        pastaRaizPrimaria: destino,
        pastaBackup: resultado.pastaBackup,
      );

      await repository.atualizarUltimoBackupAutomaticoMs(
        resultado.criadoEm.millisecondsSinceEpoch,
      );
      await repository.limparFalhaBackupAutomatico();
      return 0;
    } catch (_) {
      try {
        await repository.registrarFalhaBackupAutomatico(
          'Falha no backup agendado (tarefa Windows)',
        );
      } catch (_) {}
      return 1;
    }
  }
}

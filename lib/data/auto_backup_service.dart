import 'dart:io';

import '../domain/auditoria_catalogo.dart';
import 'app_config_repository.dart';
import 'backup_pos_execucao_service.dart';
import 'objectbox.dart';
import '../services/auditoria_registrar.dart';
import 'local_backup_service.dart';
import 'sync/lan_sync_scheduler.dart';

/// Executa backup em disco quando [EmpresaConfig.backupAutomaticoAtivo] e a
/// pasta estao definidos e ja passou o intervalo desde o ultimo backup.
class AutoBackupService {
  AutoBackupService._();

  static bool _emExecucao = false;

  static bool get emExecucao => _emExecucao;

  static Future<void> tentarExecutarSeDevido(
    AppConfigRepository repository, {
    ObjectBox? objectBox,
    LanSyncScheduler? lanSyncScheduler,
  }) async {
    if (_emExecucao) return;
    final config = await repository.carregarEmpresaConfig();
    if (!config.backupAutomaticoAtivo) return;
    final pasta = config.backupAutomaticoPasta.trim();
    if (pasta.isEmpty) return;

    final intervalo = Duration(
      minutes: config.backupAutomaticoIntervaloMinutos.clamp(15, 10080),
    );
    final agora = DateTime.now();
    final ultimoMs = config.ultimoBackupAutomaticoMs;
    if (ultimoMs > 0) {
      final ultimo = DateTime.fromMillisecondsSinceEpoch(ultimoMs);
      if (!agora.subtract(intervalo).isAfter(ultimo)) {
        return;
      }
    }

    final destinoRaiz = Directory(pasta);
    if (!destinoRaiz.existsSync()) {
      await repository.registrarFalhaBackupAutomatico(
        'Pasta de backup automatico inacessivel: $pasta',
      );
      return;
    }

    if (objectBox == null) return;

    _emExecucao = true;
    try {
      final escopo = await repository.carregarBackupAutomaticoEscopo();
      final resultado = await LocalBackupService.executar(
        destinoRaiz: destinoRaiz,
        tipo: LocalBackupTipo.automatico,
        nomeLoja: config.nomeLoja,
        objectBox: objectBox,
        escopo: escopo,
        lanSyncScheduler: lanSyncScheduler,
      );

      await BackupPosExecucaoService.aposBackupSucesso(
        repository: repository,
        pastaRaizPrimaria: destinoRaiz,
        pastaBackup: resultado.pastaBackup,
      );

      await repository.atualizarUltimoBackupAutomaticoMs(
        DateTime.now().millisecondsSinceEpoch,
      );
      await repository.limparFalhaBackupAutomatico();
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupAutomatico,
        usuarioLogin: 'sistema',
        resumo: 'Backup automatico executado',
        detalhes: {'caminho': resultado.pastaBackup.path},
      );
    } catch (e) {
      await repository.registrarFalhaBackupAutomatico(e.toString());
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupFalha,
        usuarioLogin: 'sistema',
        resumo: 'Falha no backup automatico',
        detalhes: {'erro': e.toString(), 'pasta': pasta},
      );
    } finally {
      _emExecucao = false;
    }
  }
}

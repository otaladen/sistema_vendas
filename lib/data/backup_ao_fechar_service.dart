import 'dart:io';

import '../domain/auditoria_catalogo.dart';
import '../services/auditoria_registrar.dart';
import 'app_config_repository.dart';
import 'auto_backup_service.dart';
import 'backup_pos_execucao_service.dart';
import 'local_backup_service.dart';
import 'objectbox.dart';
import 'sync/lan_sync_scheduler.dart';

/// Backup opcional ao fechar o app ou sair da sessao (Fase 2).
class BackupAoFecharService {
  BackupAoFecharService._();

  static bool _emExecucao = false;
  static bool _executouNestaSessao = false;

  static Future<void> tentarSeAtivo({
    required AppConfigRepository repository,
    required ObjectBox objectBox,
    LanSyncScheduler? lanSyncScheduler,
    required String nomeLoja,
  }) async {
    if (_emExecucao || _executouNestaSessao) return;
    if (AutoBackupService.emExecucao) return;

    final ativo = await repository.carregarBackupAoFecharAtivo();
    if (!ativo) return;

    final config = await repository.carregarEmpresaConfig();
    final manual = await repository.carregarRegistroBackupManual();
    final destino = _resolverPastaDestino(config, manual);
    if (destino == null) return;

    _emExecucao = true;
    try {
      final resultado = await LocalBackupService.executar(
        destinoRaiz: destino,
        tipo: LocalBackupTipo.automatico,
        nomeLoja: nomeLoja,
        objectBox: objectBox,
        lanSyncScheduler: lanSyncScheduler,
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

      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupAutomatico,
        usuarioLogin: 'sistema',
        resumo: 'Backup ao fechar executado',
        detalhes: {'caminho': resultado.pastaBackup.path},
      );

      _executouNestaSessao = true;
    } catch (e) {
      await repository.registrarFalhaBackupAutomatico(e.toString());
    } finally {
      _emExecucao = false;
    }
  }

  static Directory? _resolverPastaDestino(
    EmpresaConfig config,
    BackupRegistroManual manual,
  ) {
    var pasta = config.backupAutomaticoPasta.trim();
    if (pasta.isEmpty) {
      pasta = manual.pastaPadrao.trim();
    }
    if (pasta.isEmpty) return null;
    final dir = Directory(pasta);
    if (!dir.existsSync()) return null;
    return dir;
  }
}

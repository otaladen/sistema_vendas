import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../domain/auditoria_catalogo.dart';
import 'objectbox.dart';
import '../services/auditoria_registrar.dart';
import 'app_config_repository.dart';
import 'local_app_data_paths.dart';
import 'local_backup_copy.dart';
import 'sync/lan_sync_scheduler.dart';

/// Executa backup em disco quando [EmpresaConfig.backupAutomaticoAtivo] e a
/// pasta estao definidos e ja passou o intervalo desde o ultimo backup.
class AutoBackupService {
  AutoBackupService._();

  static bool _emExecucao = false;

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
      return;
    }

    _emExecucao = true;
    var syncParada = false;
    try {
      final baseDadosDir = await obterDiretorioBaseDadosApp();
      if (!baseDadosDir.existsSync()) {
        return;
      }

      if (lanSyncScheduler != null && lanSyncScheduler.estaAgendado) {
        await lanSyncScheduler.parar();
        syncParada = true;
      }
      if (objectBox != null) {
        await objectBox.fecharParaCopiaDeArquivos();
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(agora);
      final pastaBackup = Directory(
        p.join(destinoRaiz.path, 'backup_sistema_vendas_$timestamp'),
      );
      pastaBackup.createSync(recursive: true);
      await copiarDiretorioRecursivo(
        origem: baseDadosDir,
        destino: Directory(p.join(pastaBackup.path, 'dados_aplicacao')),
      );

      await repository.atualizarUltimoBackupAutomaticoMs(
        DateTime.now().millisecondsSinceEpoch,
      );
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupAutomatico,
        usuarioLogin: 'sistema',
        resumo: 'Backup automatico executado',
        detalhes: {'caminho': pastaBackup.path},
      );
    } catch (_) {
      // Silencioso: disco cheio/rede indisponivel; usuario ve status em Configuracoes.
    } finally {
      if (objectBox != null) {
        try {
          await objectBox.reabrirAposCopiaDeArquivos();
        } catch (_) {}
      }
      if (syncParada && lanSyncScheduler != null) {
        try {
          await lanSyncScheduler.iniciar();
        } catch (_) {}
      }
      _emExecucao = false;
    }
  }
}

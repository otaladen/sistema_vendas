import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../domain/auditoria_catalogo.dart';
import '../domain/sessao_operacional_guard.dart';
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
    // TODO(backlog): Trava global de execucao simultanea (mutex/lock) entre
    // AutoBackupService, "Executar backup agora", backup ao fechar, headless
    // e remoto — mapeada para versoes futuras. Por ora mantem apenas a flag
    // booleana `_emExecucao` em memoria neste servico.
    if (_emExecucao) return;
    // Celular: backup automatico fecha o ObjectBox e congela o app.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return;
    // Fecha o ObjectBox: nao interromper PDV aberto (use backup agendado headless).
    if (SessaoOperacionalGuard.pdvEmUso) return;
    final config = await repository.carregarEmpresaConfig();
    if (!config.backupAutomaticoAtivo) return;
    final pasta = config.backupAutomaticoPasta.trim();
    if (pasta.isEmpty) {
      // Evita agendamento fantasma: automatico ligado sem destino.
      await repository.salvarEmpresaConfig(
        config.copyWith(backupAutomaticoAtivo: false),
      );
      await repository.registrarFalhaBackupAutomatico(
        'Backup automatico desativado: pasta de destino nao configurada.',
      );
      return;
    }

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

    // Revalida: pode ter aberto PDV durante a checagem de config.
    if (SessaoOperacionalGuard.pdvEmUso) return;

    _emExecucao = true;
    try {
      // Reserva o horario antes da copia longa: se ultimoMs estava 0 (ou a
      // gravacao atrasar), o timer de 5 min nao dispara outra copia em paralelo.
      final reservadoMs = DateTime.now().millisecondsSinceEpoch;
      await repository.atualizarUltimoBackupAutomaticoMs(reservadoMs);

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

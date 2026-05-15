import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'app_config_repository.dart';
import 'local_app_data_paths.dart';
import 'local_backup_copy.dart';

/// Executa backup em disco quando [EmpresaConfig.backupAutomaticoAtivo] e a
/// pasta estao definidos e ja passou o intervalo desde o ultimo backup.
class AutoBackupService {
  AutoBackupService._();

  static bool _emExecucao = false;

  static Future<void> tentarExecutarSeDevido(
    AppConfigRepository repository,
  ) async {
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
    try {
      final baseDadosDir = await obterDiretorioBaseDadosApp();
      if (!baseDadosDir.existsSync()) {
        return;
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
    } catch (_) {
      // Silencioso: disco cheio/rede indisponivel; usuario ve status em Configuracoes.
    } finally {
      _emExecucao = false;
    }
  }
}

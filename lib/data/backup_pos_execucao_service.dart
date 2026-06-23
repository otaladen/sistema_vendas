import 'dart:io';

import 'app_config_repository.dart';
import 'backup_retencao_service.dart';
import 'backup_segundo_destino_service.dart';

/// Retencao, espelhamento e pos-processamento apos backup bem-sucedido.
class BackupPosExecucaoService {
  BackupPosExecucaoService._();

  static Future<void> aposBackupSucesso({
    required AppConfigRepository repository,
    required Directory pastaRaizPrimaria,
    required Directory pastaBackup,
  }) async {
    final config = await repository.carregarEmpresaConfig();

    await BackupRetencaoService.aplicar(
      pastaRaiz: pastaRaizPrimaria,
      maxCopias: config.backupRetencaoMaxCopias,
    );

    if (config.backupSegundoDestinoAtivo) {
      final secundaria = config.backupSegundoDestinoPasta.trim();
      if (secundaria.isNotEmpty) {
        await BackupSegundoDestinoService.espelhar(
          pastaBackup: pastaBackup,
          pastaRaizSecundaria: Directory(secundaria),
          maxCopias: config.backupRetencaoMaxCopias,
        );
      }
    }
  }
}

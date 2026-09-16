import 'dart:io';

import 'app_config_repository.dart';
import 'backup_destino_resolver.dart';
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
      if (BackupDestinoResolver.caminhoConfiguradoValido(secundaria)) {
        final dirSec = Directory(secundaria);
        if (!dirSec.existsSync()) {
          dirSec.createSync(recursive: true);
        }
        await BackupSegundoDestinoService.espelhar(
          pastaBackup: pastaBackup,
          pastaRaizSecundaria: dirSec,
          maxCopias: config.backupRetencaoMaxCopias,
        );
      }
    }
  }
}

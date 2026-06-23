import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/auditoria_catalogo.dart';
import '../services/auditoria_registrar.dart';
import 'backup_retencao_service.dart';
import 'local_backup_copy.dart';

/// Copia espelhada do backup para pasta secundaria (rede, nuvem, servidor).
class BackupSegundoDestinoService {
  BackupSegundoDestinoService._();

  static Future<void> espelhar({
    required Directory pastaBackup,
    required Directory pastaRaizSecundaria,
    required int maxCopias,
  }) async {
    if (!pastaBackup.existsSync()) return;
    if (!pastaRaizSecundaria.existsSync()) {
      pastaRaizSecundaria.createSync(recursive: true);
    }

    final destino = Directory(
      p.join(pastaRaizSecundaria.path, p.basename(pastaBackup.path)),
    );
    if (destino.existsSync()) {
      await destino.delete(recursive: true);
    }

    await copiarDiretorioRecursivo(
      origem: pastaBackup,
      destino: destino,
    );

    await BackupRetencaoService.aplicar(
      pastaRaiz: pastaRaizSecundaria,
      maxCopias: maxCopias,
    );

    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.backup,
      acao: AuditoriaAcao.backupSegundoDestino,
      usuarioLogin: 'sistema',
      resumo: 'Backup espelhado no segundo destino',
      detalhes: {
        'origem': pastaBackup.path,
        'destino': destino.path,
      },
    );
  }
}

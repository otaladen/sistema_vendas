import 'dart:io';

import '../domain/auditoria_catalogo.dart';
import '../domain/backup_retencao.dart';
import '../services/auditoria_registrar.dart';
import 'backup_historico_service.dart';

/// Remove backups antigos quando excede a politica de retencao.
class BackupRetencaoService {
  BackupRetencaoService._();

  static Future<int> aplicar({
    required Directory pastaRaiz,
    required int maxCopias,
  }) async {
    final limite = BackupRetencaoOpcoes.normalizar(maxCopias);
    if (limite <= 0 || !pastaRaiz.existsSync()) return 0;

    final itens = await BackupHistoricoService.listar(
      pastasRaiz: [pastaRaiz.path],
      limite: 1000,
    );
    if (itens.length <= limite) return 0;

    var removidos = 0;
    for (final item in itens.sublist(limite)) {
      try {
        if (item.pasta.existsSync()) {
          await item.pasta.delete(recursive: true);
          removidos++;
        }
      } catch (_) {}
    }

    if (removidos > 0) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupRetencao,
        usuarioLogin: 'sistema',
        resumo: 'Retencao: $removidos backup(s) antigo(s) removido(s)',
        detalhes: {
          'pasta': pastaRaiz.path,
          'limite': limite,
          'removidos': removidos,
        },
      );
    }

    return removidos;
  }
}

import 'dart:io';

import '../domain/auditoria_catalogo.dart';
import '../domain/backup_historico_item.dart';
import '../domain/backup_retencao.dart';
import '../domain/local_backup_escopo.dart';
import '../services/auditoria_registrar.dart';
import 'backup_historico_service.dart';

/// Remove backups antigos quando excede a politica de retencao.
class BackupRetencaoService {
  BackupRetencaoService._();

  static Future<int> aplicar({
    required Directory pastaRaiz,
    required int maxCopiasLeves,
    required int maxCopiasCompletos,
  }) async {
    if (!pastaRaiz.existsSync()) return 0;
    final limiteLeves = BackupRetencaoOpcoes.normalizar(maxCopiasLeves);
    final limiteCompletos =
        BackupRetencaoCompletosOpcoes.normalizar(maxCopiasCompletos);

    final itens = await BackupHistoricoService.listar(
      pastasRaiz: [pastaRaiz.path],
      limite: 1000,
    );
    final leves = itens
        .where((e) => e.escopo.classeRetencao == BackupClasseRetencao.leve)
        .toList();
    final completos = itens
        .where((e) => e.escopo.classeRetencao == BackupClasseRetencao.completo)
        .toList();

    final removidosLeves = await _removerExcedentes(leves, limiteLeves);
    final removidosCompletos =
        await _removerExcedentes(completos, limiteCompletos);
    final removidos = removidosLeves + removidosCompletos;

    if (removidos > 0) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.backup,
        acao: AuditoriaAcao.backupRetencao,
        usuarioLogin: 'sistema',
        resumo: 'Retencao: $removidos backup(s) antigo(s) removido(s)',
        detalhes: {
          'pasta': pastaRaiz.path,
          'limiteLeves': limiteLeves,
          'limiteCompletos': limiteCompletos,
          'removidosLeves': removidosLeves,
          'removidosCompletos': removidosCompletos,
        },
      );
    }

    return removidos;
  }

  /// [itens] vem do mais novo para o mais antigo. Limite 0 nao apaga.
  static Future<int> _removerExcedentes(
    List<BackupHistoricoItem> itens,
    int limite,
  ) async {
    if (limite <= 0 || itens.length <= limite) return 0;
    var removidos = 0;
    for (final item in itens.sublist(limite)) {
      try {
        if (item.pasta.existsSync()) {
          await item.pasta.delete(recursive: true);
          removidos++;
        }
      } catch (_) {}
    }
    return removidos;
  }
}

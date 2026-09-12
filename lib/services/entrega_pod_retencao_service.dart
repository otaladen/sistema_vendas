import 'dart:io';

import '../data/app_config_repository.dart';
import 'configuracoes_service.dart';
import '../domain/auditoria_catalogo.dart';
import '../domain/pod_foto_retencao.dart';
import 'auditoria_registrar.dart';
import 'entrega_pod_paths.dart';

/// Apaga JPEGs de POD mais velhos que a politica configurada.
class EntregaPodRetencaoService {
  EntregaPodRetencaoService._();

  static Future<int> aplicarSeConfigurado([
    AppConfigRepository? configRepository,
  ]) async {
    try {
      final repo =
          configRepository ?? ConfiguracoesService.repositoryFallback();
      final config = await repo.carregarEmpresaConfig();
      return aplicar(dias: config.podFotoRetencaoDias);
    } catch (_) {
      return 0;
    }
  }

  static Future<int> aplicar({required int dias}) async {
    final limite = PodFotoRetencaoOpcoes.normalizar(dias);
    if (limite <= 0) return 0;

    final corte = DateTime.now().subtract(Duration(days: limite));
    var removidos = 0;

    final pastas = <Directory>[];
    final servidor = EntregaPodPaths.diretorioServidorSeExistir();
    if (servidor != null) pastas.add(servidor);
    try {
      pastas.add(await EntregaPodPaths.diretorioLocal());
    } catch (_) {}
    try {
      pastas.add(await EntregaPodPaths.diretorioCache());
    } catch (_) {}

    final vistos = <String>{};
    for (final dir in pastas) {
      final chave = dir.absolute.path.toLowerCase();
      if (!vistos.add(chave)) continue;
      removidos += await _purgarPasta(dir, corte);
    }

    if (removidos > 0) {
      try {
        AuditoriaRegistrar.registrar(
          modulo: AuditoriaModulo.sistema,
          acao: AuditoriaAcao.retencaoAutomatica,
          usuarioLogin: 'sistema',
          entidade: 'pod_foto',
          resumo:
              'Retencao POD: $removidos foto(s) removida(s) (politica $limite dias)',
          detalhes: {
            'diasRetencao': limite,
            'removidos': removidos,
          },
        );
      } catch (_) {}
    }
    return removidos;
  }

  static Future<int> _purgarPasta(Directory dir, DateTime corte) async {
    if (!dir.existsSync()) return 0;
    var n = 0;
    try {
      await for (final ent in dir.list(followLinks: false)) {
        if (ent is! File) continue;
        final nome = ent.path.toLowerCase();
        if (!nome.endsWith('.jpg') && !nome.endsWith('.jpeg')) continue;
        DateTime? quando;
        try {
          quando = ent.lastModifiedSync();
        } catch (_) {}
        if (quando == null || !quando.isBefore(corte)) continue;
        try {
          await ent.delete();
          n++;
        } catch (_) {}
      }
    } catch (_) {}
    return n;
  }
}

import '../data/app_config_repository.dart';
import '../data/auditoria_repository.dart';
import '../domain/auditoria_catalogo.dart';
import '../domain/auditoria_retencao.dart';
import 'auditoria_registrar.dart';

/// Aplica politica de retencao do log na inicializacao do app.
class AuditoriaRetencaoService {
  AuditoriaRetencaoService._();

  static Future<int> aplicarSeConfigurado({
    required AppConfigRepository configRepository,
    required AuditoriaRepository auditoriaRepository,
  }) async {
    final config = await configRepository.carregarEmpresaConfig();
    final dias = AuditoriaRetencaoOpcoes.normalizar(config.auditoriaRetencaoDias);
    if (dias <= 0) return 0;

    final removidos = auditoriaRepository.purgarAnterioresARetencaoDias(dias);
    if (removidos > 0) {
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.sistema,
        acao: AuditoriaAcao.retencaoAutomatica,
        usuarioLogin: 'sistema',
        entidade: 'auditoria_evento',
        resumo:
            'Retencao automatica: $removidos evento(s) removidos (politica $dias dias)',
        detalhes: {
          'diasRetencao': dias,
          'removidos': removidos,
        },
      );
    }
    return removidos;
  }
}

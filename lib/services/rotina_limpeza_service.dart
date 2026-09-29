import '../data/app_config_repository.dart';
import '../data/auditoria_repository.dart';
import '../data/objectbox.dart';
import '../data/sugestao_venda_metrica_repository.dart';
import 'auditoria_retencao_service.dart';

/// Expurga historico local que nao precisa ficar no banco do balcao.
class RotinaLimpezaResultado {
  const RotinaLimpezaResultado({
    required this.metricasRemovidas,
    required this.auditoriasRemovidas,
  });

  final int metricasRemovidas;
  final int auditoriasRemovidas;
}

class RotinaLimpezaService {
  RotinaLimpezaService._();

  /// Janela da metrica de sugestao no PDV. Nao segue o interruptor da auditoria.
  static const int diasRetencaoMetricaSugestao = 90;

  static Future<RotinaLimpezaResultado> aplicar({
    required ObjectBox db,
    required AppConfigRepository configRepository,
    required AuditoriaRepository auditoriaRepository,
  }) async {
    final metricas = SugestaoVendaMetricaRepository(db).purgarAnterioresA(
      diasRetencaoMetricaSugestao,
    );
    final auditorias = await AuditoriaRetencaoService.aplicarSeConfigurado(
      configRepository: configRepository,
      auditoriaRepository: auditoriaRepository,
    );
    return RotinaLimpezaResultado(
      metricasRemovidas: metricas,
      auditoriasRemovidas: auditorias,
    );
  }
}

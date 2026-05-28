import '../data/app_config_repository.dart';
import '../model/venda.dart';
import 'entrega_pod_lan_service.dart';

/// Baixa fotos POD para cache apos sync ou ao abrir entregas.
class EntregaPodPrefetchService {
  EntregaPodPrefetchService({
    required AppConfigRepository configRepository,
    EntregaPodLanService? lanService,
  })  : _configRepository = configRepository,
        _lanService = lanService;

  final AppConfigRepository _configRepository;
  final EntregaPodLanService? _lanService;

  Future<int> prefetchLista(Iterable<Venda> entregas) async {
    final lan = _lanService ??
        EntregaPodLanService(configRepository: _configRepository);
    var baixadas = 0;
    for (final v in entregas) {
      final servidor = v.podFotoPathServidor.trim();
      if (servidor.isEmpty) continue;
      final path = await lan.baixarParaCache(
        podFotoPathServidor: servidor,
        podFotoPathLocal: v.podFotoPath,
      );
      if (path != null) baixadas++;
    }
    return baixadas;
  }
}

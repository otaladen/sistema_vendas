import '../../domain/sugestao_venda_ranking.dart';
import 'lan_api_client.dart';

/// Ranking de sugestoes de venda via API.
class SugestaoVendaMetricaApiRepository {
  SugestaoVendaMetricaApiRepository(this._client);

  final LanApiClient _client;

  Future<List<SugestaoVendaRankingLinha>> listarRanking({
    required DateTime inicio,
    required DateTime fim,
    int limite = 200,
  }) async {
    final raw = await _client.listarSugestoesVendaRanking(
      desde: inicio,
      ate: fim,
      limit: limite,
    );
    return raw
        .map(
          (m) => SugestaoVendaRankingLinha(
            produtoOrigemId: (m['produtoOrigemId'] as num?)?.toInt() ?? 0,
            produtoSugeridoId: (m['produtoSugeridoId'] as num?)?.toInt() ?? 0,
            fonte: (m['fonte'] ?? '').toString(),
            exibicoes: (m['exibicoes'] as num?)?.toInt() ?? 0,
            aceites: (m['aceites'] as num?)?.toInt() ?? 0,
            ignorados: (m['ignorados'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
  }
}

import 'lan_api_client.dart';

/// Conferencia de carga via API (cache em memoria por escopo).
class ConferenciaCargaApiRepository {
  ConferenciaCargaApiRepository(this._client);

  final LanApiClient _client;
  final Map<String, Map<String, bool>> _cache = {};

  Map<String, bool> mapaPorEscopo(String escopoViagem) {
    final escopo = escopoViagem.trim();
    if (escopo.isEmpty) return {};
    return Map<String, bool>.from(_cache[escopo] ?? const {});
  }

  Future<void> hidratarEscopo(String escopoViagem) async {
    final escopo = escopoViagem.trim();
    if (escopo.isEmpty) return;
    final m = await _client.obterConferenciaCarga(escopo);
    final mapa = <String, bool>{};
    final items = m['items'];
    if (items is List) {
      for (final raw in items.whereType<Map>()) {
        final e = Map<String, dynamic>.from(raw);
        final chave = (e['chaveProduto'] ?? '').toString().trim();
        if (chave.isEmpty) continue;
        mapa[chave] = e['conferido'] == true;
      }
    }
    _cache[escopo] = mapa;
  }

  void salvarConferencia({
    required String escopoViagem,
    required String chaveProduto,
    required bool conferido,
    String usuarioLogin = '',
    void Function(Object erro)? onErro,
  }) {
    final escopo = escopoViagem.trim();
    final chave = chaveProduto.trim();
    if (escopo.isEmpty || chave.isEmpty) return;
    final mapa = _cache.putIfAbsent(escopo, () => <String, bool>{});
    mapa[chave] = conferido;
    _client
        .salvarConferenciaCarga(
          escopoViagem: escopo,
          chaveProduto: chave,
          conferido: conferido,
          usuarioLogin: usuarioLogin,
        )
        .then((_) {})
        .catchError((Object e) {
          // Reverte cache local se a gravacao remota falhar.
          mapa[chave] = !conferido;
          onErro?.call(e);
        });
  }

  /// Variante async com propagacao de [LanApiException].
  Future<void> salvarConferenciaRemoto({
    required String escopoViagem,
    required String chaveProduto,
    required bool conferido,
    String usuarioLogin = '',
  }) async {
    final escopo = escopoViagem.trim();
    final chave = chaveProduto.trim();
    if (escopo.isEmpty || chave.isEmpty) return;
    final mapa = _cache.putIfAbsent(escopo, () => <String, bool>{});
    final anterior = mapa[chave] ?? false;
    mapa[chave] = conferido;
    try {
      await _client.salvarConferenciaCarga(
        escopoViagem: escopo,
        chaveProduto: chave,
        conferido: conferido,
        usuarioLogin: usuarioLogin,
      );
    } catch (e) {
      mapa[chave] = anterior;
      rethrow;
    }
  }

  int contarConferidos(String escopoViagem, Iterable<String> chavesProduto) {
    final mapa = mapaPorEscopo(escopoViagem);
    var n = 0;
    for (final c in chavesProduto) {
      if (mapa[c] == true) n++;
    }
    return n;
  }
}

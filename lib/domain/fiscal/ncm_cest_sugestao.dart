/// Sugestao de CEST a partir do NCM (loja de materiais / construcao).
///
/// Base: itens frequentes do Convenio ICMS 92/2015 (anexo CEST),
/// com casamento por NCM completo e depois por prefixo (6 / 4 digitos).
/// E uma **sugestao de cadastro** — o usuario deve validar com o contador.
class NcmCestSugestao {
  NcmCestSugestao._();

  /// NCM (8 digitos) ou prefixo → CEST (7 digitos, sem pontuacao).
  /// Ordem: entradas mais especificas primeiro (o resolver tenta 8→6→4).
  static const Map<String, String> _porPrefixoNcm = {
    // Cimento / cal / gesso
    '252329': '1000100', // cimentos Portland
    '2523': '1000100',
    '252210': '1000200', // cal viva
    '2522': '1000200',
    '252020': '1000400', // gesso
    '2520': '1000400',

    // Areia, brita, pedras
    '250510': '1001800',
    '2505': '1001800',
    '251710': '1001900',
    '2517': '1001900',

    // Argamassa, rejunte, mastiques
    '321490': '1001400',
    '3214': '1001400',

    // Tintas e vernizes (segmento construcao)
    '320810': '1001000',
    '320820': '1001000',
    '320890': '1001000',
    '3208': '1001000',
    '320910': '1001000',
    '320990': '1001000',
    '3209': '1001000',
    '321000': '1001000',
    '3210': '1001000',

    // Tubos / conexoes plasticos (PVC etc.)
    '391721': '1000600',
    '391722': '1000600',
    '391723': '1000600',
    '391729': '1000600',
    '3917': '1000600',
    '391740': '1000700',

    // Tubos / conexoes metalicos
    '730630': '1000600',
    '7306': '1000600',
    '730711': '1000700',
    '7307': '1000700',

    // Torneiras, registros, misturadores
    '848180': '1000800',
    '8481': '1000800',

    // Telhas / chapas fibrocimento / similares
    '681182': '1000300',
    '6811': '1000300',
    '690510': '1000300',
    '6905': '1000300',

    // Caixas d'agua / reservatorios plasticos
    '392510': '1000500',
    '3925': '1000500',

    // Fios e cabos eletricos (segmento 09 — eletricos comuns na loja)
    '854449': '0900500',
    '8544': '0900500',

    // Disjuntores / aparelhos protecao circuitos
    '853620': '0900300',
    '8536': '0900300',

    // Lampadas LED
    '853950': '0900700',
    '8539': '0900700',

    // Ferramentas manuais (quando enquadradas em ST regional — sugestao)
    '820411': '2100100',
    '8205': '2100200',
  };

  /// Normaliza NCM para 8 digitos (somente numeros).
  static String normalizarNcm(String? ncm) {
    final d = (ncm ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length > 8) return d.substring(0, 8);
    return d;
  }

  /// Normaliza CEST para 7 digitos.
  static String normalizarCest(String? cest) {
    final d = (cest ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length > 7) return d.substring(0, 7);
    return d;
  }

  /// Formata CEST para exibicao `AA.BBB.CC`.
  static String formatarCestExibicao(String cest7) {
    final d = normalizarCest(cest7);
    if (d.length != 7) return d;
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5)}';
  }

  /// Retorna CEST de 7 digitos ou `null` se nao houver sugestao.
  static String? sugerirCest(String? ncm) {
    final digitos = normalizarNcm(ncm);
    if (digitos.length != 8) return null;

    for (final len in const [8, 6, 4]) {
      if (digitos.length < len) continue;
      final chave = digitos.substring(0, len);
      final cest = _porPrefixoNcm[chave];
      if (cest != null) {
        final n = normalizarCest(cest);
        if (n.length == 7) return n;
      }
    }
    return null;
  }

  /// Se [cestAtual] estiver vazio, devolve sugestao; senao mantem o atual.
  static String preencherSeVazio({
    required String? ncm,
    required String? cestAtual,
  }) {
    final atual = normalizarCest(cestAtual);
    if (atual.length == 7) return atual;
    return sugerirCest(ncm) ?? '';
  }
}

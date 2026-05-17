/// Configuracao da busca de foto de produto na web.
///
/// Padrao: [ProvedorBuscaImagem.duckduckgo] — **100% gratuito**, sem API key.
///
/// Google Custom Search: fechado para contas novas.
/// Brave Search: pago apos creditos mensais (opcional).
class BuscaImagemConfig {
  const BuscaImagemConfig._();

  /// Provedor ativo (recomendado: duckduckgo).
  static const ProvedorBuscaImagem provedor = ProvedorBuscaImagem.duckduckgo;

  // --- Opcional: Brave Search (pago) ---
  static const String braveApiKey = '';

  static const String braveApiBaseUrl =
      'https://api.search.brave.com/res/v1/images/search';

  static const String urlCadastroBraveApi =
      'https://api-dashboard.search.brave.com/register';

  // --- Opcional: Google Custom Search (clientes antigos) ---
  static const String googleApiBaseUrl =
      'https://www.googleapis.com/customsearch/v1';

  static const String googleApiKey = '';

  static const String googleSearchEngineId = '';

  static bool get configuradoBrave => braveApiKey.trim().isNotEmpty;

  static bool get configuradoGoogle =>
      googleApiKey.trim().isNotEmpty &&
      googleSearchEngineId.trim().isNotEmpty;

  static bool get configurado {
    switch (provedor) {
      case ProvedorBuscaImagem.duckduckgo:
        return true;
      case ProvedorBuscaImagem.brave:
        return configuradoBrave;
      case ProvedorBuscaImagem.google:
        return configuradoGoogle;
    }
  }
}

enum ProvedorBuscaImagem {
  /// Gratuito, sem cadastro.
  duckduckgo,
  brave,
  google,
}

/// Exemplo — copie os valores para `busca_imagem_config.dart`.
class BuscaImagemConfig {
  const BuscaImagemConfig._();

  static const String apiBaseUrl =
      'https://www.googleapis.com/customsearch/v1';

  static const String googleApiKey = 'AIzaSy...';
  static const String googleSearchEngineId = 'c47b94d2fa90c4654';

  static bool get configurado =>
      googleApiKey.trim().isNotEmpty && googleSearchEngineId.trim().isNotEmpty;
}

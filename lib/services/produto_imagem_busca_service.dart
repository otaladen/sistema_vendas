import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/busca_imagem_config.dart';

/// Metadado de uma imagem encontrada na busca.
class ImagemProdutoEncontrada {
  const ImagemProdutoEncontrada({
    required this.url,
    this.titulo = '',
    this.fonte = '',
  });

  final String url;
  final String titulo;
  final String fonte;
}

class BuscaImagemConfigException implements Exception {
  BuscaImagemConfigException(this.message, {this.instrucoesCorrecao});
  final String message;
  final List<String>? instrucoesCorrecao;
  @override
  String toString() => message;
}

class BuscaImagemException implements Exception {
  BuscaImagemException(
    this.message, {
    this.cause,
    this.codigoErro,
    this.urlAtivacao,
    this.instrucoesCorrecao,
  });
  final String message;
  final Object? cause;
  final String? codigoErro;
  final String? urlAtivacao;
  final List<String>? instrucoesCorrecao;

  bool get apiNaoHabilitada => codigoErro == 'API_NOT_ENABLED';

  bool get chaveBloqueada => codigoErro == 'API_KEY_SERVICE_BLOCKED';

  bool get googleFechadoNovosClientes =>
      codigoErro == 'GOOGLE_CUSTOM_SEARCH_CLOSED';

  @override
  String toString() =>
      cause != null ? '$message ($cause)' : message;
}

/// Busca imagens de produto na web (DuckDuckGo gratuito por padrao).
class ProdutoImagemBuscaService {
  ProdutoImagemBuscaService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const Duration _timeout = Duration(seconds: 25);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

  /// Headers exigidos pelo DuckDuckGo para liberar i.js (evita HTTP 403).
  static Map<String, String> get _headersDuckDuckGo => {
        'User-Agent': _userAgent,
        'Accept': '*/*',
        'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
        'Referer': 'https://duckduckgo.com/',
        'Origin': 'https://duckduckgo.com',
        'Sec-GPC': '1',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      };

  static final RegExp _regexVqd = RegExp(r'vqd=([\w-]+)');

  /// Query: nome + marca + "material de construcao".
  static String montarTermoBusca({
    required String nome,
    String marca = '',
  }) {
    final partes = <String>[];
    final nomeLimpo = nome.trim();
    final marcaLimpa = marca.trim();

    if (nomeLimpo.isNotEmpty) {
      partes.add(nomeLimpo);
    }
    if (marcaLimpa.isNotEmpty &&
        !nomeLimpo.toLowerCase().contains(marcaLimpa.toLowerCase())) {
      partes.add(marcaLimpa);
    }
    partes.add('material de construcao');
    return partes.join(' ').trim();
  }

  Future<List<ImagemProdutoEncontrada>> buscarImagens(
    String termo, {
    int limite = 5,
  }) async {
    final q = termo.trim();
    if (q.isEmpty) {
      return [];
    }
    if (!BuscaImagemConfig.configurado) {
      throw BuscaImagemConfigException(
        'Busca de imagem nao configurada.',
        instrucoesCorrecao: const [
          'Em busca_imagem_config.dart use provedor = duckduckgo (gratis).',
        ],
      );
    }

    switch (BuscaImagemConfig.provedor) {
      case ProvedorBuscaImagem.duckduckgo:
        return _buscarImagensDuckDuckGo(q, limite: limite);
      case ProvedorBuscaImagem.brave:
        return _buscarImagensBrave(q, limite: limite);
      case ProvedorBuscaImagem.google:
        return _buscarImagensGoogle(q, limite: limite);
    }
  }

  /// Busca gratuita via DuckDuckGo (sem API key).
  Future<List<ImagemProdutoEncontrada>> _buscarImagensDuckDuckGo(
    String termo, {
    required int limite,
  }) async {
    final pagina = await _http
        .get(
          Uri.https('duckduckgo.com', '/', {'q': termo}),
          headers: _headersDuckDuckGo,
        )
        .timeout(_timeout);

    if (pagina.statusCode != 200) {
      throw BuscaImagemException(
        'Nao foi possivel iniciar busca de imagens (HTTP ${pagina.statusCode}).',
      );
    }

    final matchVqd = _regexVqd.firstMatch(pagina.body);
    final vqd = matchVqd?.group(1);
    if (vqd == null || vqd.isEmpty) {
      throw BuscaImagemException(
        'Busca de imagens indisponivel no momento. Tente de novo em instantes.',
        codigoErro: 'DDG_VQD_MISSING',
      );
    }

    final jsonResp = await _http
        .get(
          Uri.https('duckduckgo.com', '/i.js', {
            'o': 'json',
            'q': termo,
            'l': 'br-br',
            'vqd': vqd,
            'p': '1',
          }),
          headers: _headersDuckDuckGo,
        )
        .timeout(_timeout);

    if (jsonResp.statusCode == 403) {
      throw BuscaImagemException(
        'Busca de imagens bloqueada (403). Tente de novo em alguns segundos.',
        codigoErro: 'DDG_FORBIDDEN',
      );
    }
    if (jsonResp.statusCode != 200) {
      throw BuscaImagemException(
        'Busca de imagens falhou (HTTP ${jsonResp.statusCode}).',
      );
    }

    final decoded = jsonDecode(jsonResp.body);
    if (decoded is! Map<String, dynamic>) {
      return [];
    }

    final results = decoded['results'];
    if (results is! List) {
      return [];
    }

    final resultados = <ImagemProdutoEncontrada>[];
    for (final item in results) {
      if (resultados.length >= limite) break;
      if (item is! Map<String, dynamic>) continue;

      final urlImagem = (item['image'] ?? item['thumbnail'] ?? '')
          .toString()
          .trim();
      if (urlImagem.isEmpty) continue;

      resultados.add(
        ImagemProdutoEncontrada(
          url: urlImagem,
          titulo: (item['title'] ?? '').toString(),
          fonte: (item['url'] ?? '').toString(),
        ),
      );
    }
    return resultados;
  }

  Future<List<ImagemProdutoEncontrada>> _buscarImagensBrave(
    String termo, {
    required int limite,
  }) async {
    final uri = Uri.parse(BuscaImagemConfig.braveApiBaseUrl).replace(
      queryParameters: {
        'q': termo,
        'count': limite.clamp(1, 20).toString(),
        'country': 'BR',
        'search_lang': 'pt',
        'safesearch': 'strict',
      },
    );

    final response = await _http
        .get(
          uri,
          headers: {
            'X-Subscription-Token': BuscaImagemConfig.braveApiKey.trim(),
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw BuscaImagemException(
        'Chave Brave Search invalida ou sem permissao.',
        codigoErro: 'BRAVE_AUTH_ERROR',
        urlAtivacao: BuscaImagemConfig.urlCadastroBraveApi,
        instrucoesCorrecao: const [
          'Confira braveApiKey em lib/config/busca_imagem_config.dart.',
          'Gere uma chave em api-dashboard.search.brave.com',
          'Plano gratuito: cerca de 2000 buscas por mes.',
        ],
      );
    }

    if (response.statusCode != 200) {
      final msg = _extrairMensagemErro(response.body) ??
          'HTTP ${response.statusCode}';
      throw BuscaImagemException('Busca Brave falhou: $msg');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return [];
    }

    final results = decoded['results'];
    if (results is! List) {
      return [];
    }

    final resultados = <ImagemProdutoEncontrada>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;

      var urlImagem = '';
      final props = item['properties'];
      if (props is Map<String, dynamic>) {
        urlImagem = (props['url'] ?? '').toString().trim();
      }
      if (urlImagem.isEmpty) {
        final thumb = item['thumbnail'];
        if (thumb is Map<String, dynamic>) {
          urlImagem = (thumb['src'] ?? '').toString().trim();
        }
      }
      if (urlImagem.isEmpty) {
        urlImagem = (item['url'] ?? '').toString().trim();
      }
      if (urlImagem.isEmpty) continue;

      resultados.add(
        ImagemProdutoEncontrada(
          url: urlImagem,
          titulo: (item['title'] ?? '').toString(),
          fonte: (item['url'] ?? item['source'] ?? '').toString(),
        ),
      );
    }
    return resultados;
  }

  Future<List<ImagemProdutoEncontrada>> _buscarImagensGoogle(
    String termo, {
    required int limite,
  }) async {
    if (!BuscaImagemConfig.configuradoGoogle) {
      throw _erroGoogleFechadoParaNovosClientes();
    }

    final uri = Uri.parse(BuscaImagemConfig.googleApiBaseUrl).replace(
      queryParameters: {
        'key': BuscaImagemConfig.googleApiKey.trim(),
        'cx': BuscaImagemConfig.googleSearchEngineId.trim(),
        'q': termo,
        'searchType': 'image',
        'num': limite.clamp(1, 10).toString(),
        'safe': 'active',
      },
    );

    final response = await _http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw _erroRespostaHttpGoogle(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return [];
    }

    final items = decoded['items'];
    if (items is! List) {
      return [];
    }

    final resultados = <ImagemProdutoEncontrada>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final link = (item['link'] ?? '').toString().trim();
      if (link.isEmpty) continue;
      resultados.add(
        ImagemProdutoEncontrada(
          url: link,
          titulo: (item['title'] ?? '').toString(),
          fonte: (item['displayLink'] ?? '').toString(),
        ),
      );
    }
    return resultados;
  }

  Future<ImagemProdutoEncontrada?> buscarPrimeiraImagem(String termo) async {
    final lista = await buscarImagens(termo, limite: 1);
    if (lista.isEmpty) return null;
    return lista.first;
  }

  Future<String?> buscarEBaixarPrimeiraImagem(String termo) async {
    final imagens = await buscarImagens(termo, limite: 5);
    for (final img in imagens) {
      final path = await baixarParaTemporario(img.url);
      if (path != null) {
        return path;
      }
    }
    return null;
  }

  Future<String?> baixarParaTemporario(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    final response = await _http
        .get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'image/*,*/*',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return null;
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/html')) {
      return null;
    }

    final dir = await getTemporaryDirectory();
    final nome = 'busca_foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = p.join(dir.path, nome);
    await File(path).writeAsBytes(response.bodyBytes, flush: true);
    return path;
  }

  static final RegExp _regexProjectId = RegExp(r'project[=\s]+(\d+)');

  static BuscaImagemException _erroGoogleFechadoParaNovosClientes() {
    return BuscaImagemException(
      'Google Custom Search nao esta disponivel para projetos novos.',
      codigoErro: 'GOOGLE_CUSTOM_SEARCH_CLOSED',
      urlAtivacao: BuscaImagemConfig.urlCadastroBraveApi,
      instrucoesCorrecao: const [
        'O Google fechou a Custom Search JSON API para clientes novos.',
        'Ativar a API no console nao resolve o erro 403.',
        'Use Brave Search (gratis): api-dashboard.search.brave.com/register',
        'Cole a chave em braveApiKey em busca_imagem_config.dart.',
      ],
    );
  }

  static BuscaImagemException _erroRespostaHttpGoogle(int status, String body) {
    final msgApi = _extrairMensagemErro(body) ?? 'HTTP $status';
    final lower = msgApi.toLowerCase();

    if (lower.contains('does not have the access to custom search')) {
      return _erroGoogleFechadoParaNovosClientes();
    }

    if (lower.contains('api_key_service_blocked') ||
        (lower.contains('blocked') && lower.contains('customsearch'))) {
      final projectId = _regexProjectId.firstMatch(body)?.group(1);
      return BuscaImagemException(
        'A API Key esta bloqueada para Custom Search.',
        codigoErro: 'API_KEY_SERVICE_BLOCKED',
        urlAtivacao: BuscaImagemConfig.urlCadastroBraveApi,
        instrucoesCorrecao: [
          'Google Custom Search nao combina com chave Gemini.',
          'Para contas novas, use Brave Search (veja braveApiKey no config).',
          if (projectId != null) 'Projeto Google: $projectId',
        ],
      );
    }

    if (lower.contains('has not been used') ||
        lower.contains('is disabled') ||
        lower.contains('service_disabled')) {
      return BuscaImagemException(
        'Custom Search API nao habilitada no projeto.',
        codigoErro: 'API_NOT_ENABLED',
        urlAtivacao: BuscaImagemConfig.urlCadastroBraveApi,
        instrucoesCorrecao: const [
          'Para projetos novos, o Google nao libera mais esta API.',
          'Cadastre-se no Brave Search e use braveApiKey no config.',
        ],
      );
    }

    return BuscaImagemException('Busca Google falhou: $msgApi');
  }

  static String? _extrairMensagemErro(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error'];
        if (err is Map<String, dynamic>) {
          return (err['message'] ?? '').toString();
        }
        return (decoded['message'] ?? '').toString();
      }
    } catch (_) {}
    return null;
  }
}

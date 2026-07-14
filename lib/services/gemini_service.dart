import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../domain/gemini_produto_padronizado.dart';
import '../domain/preco_mercado_resultado.dart';
import 'gemini_config.dart';

/// Modelos tentados em ordem. Cada modelo tem cota separada no tier gratuito.
const List<String> _modelosGemini = [
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
  'gemini-2.0-flash',
];

const String _systemPrompt = '''
Voce e um especialista em catalogacao de materiais de construcao para lojas de varejo.

Sua tarefa e ler nomes de produtos digitados de forma abreviada, informal ou com erros
(ex.: "pvc esg 100 tigre", "arg aciii 20kg", "tinta sv piso br 18l") e devolver um
cadastro padronizado e profissional.

Regras:
- Corrija portugues (acentos, concordancia) e expanda abreviacoes do setor.
- O nome_padronizado deve ser claro para o vendedor e para a nota fiscal (marca, medida,
  bitola, peso ou volume quando fizer sentido).
- categoria_sugerida deve ser uma das categorias permitidas no schema.
- subcategoria_sugerida deve ser o tipo mais especifico do produto dentro da categoria
  (ex.: "Tubos e Conexoes", "Argamassa", "Parafusos e Buchas"). Quando houver catalogo
  da loja na mensagem do usuario, copie o texto EXATO da subcategoria listada.
- unidade_medida deve ser a unidade comercial mais adequada (UN, KG, MT, etc.).
- ncm: 8 digitos da NCM mais provavel para o item (material de construcao no Brasil).
  Deixe vazio se nao tiver seguranca razoavel.
- cest: 7 digitos quando o produto for tipico de substituicao tributaria; vazio caso contrario.
- grupo_tributario: tributado (maioria), isento ou substituicao_tributaria (materiais ST comuns
  em lojas de construcao: tintas, tubos PVC, cimentos cola, etc. — use criterio fiscal usual).
- codigo_barras: preencha SOMENTE se o GTIN/EAN estiver explicito no texto de entrada
  (8, 12, 13 ou 14 digitos). Caso contrario retorne vazio — nao invente codigo de barras.
- Nao invente precos.
- Responda apenas com o JSON exigido pelo schema.
''';

class GeminiConfigException implements Exception {
  GeminiConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiServiceException implements Exception {
  GeminiServiceException(
    this.message, {
    this.cause,
    this.codigoErro,
    this.instrucoesCorrecao,
  });
  final String message;
  final Object? cause;
  final String? codigoErro;
  final List<String>? instrucoesCorrecao;

  bool get chaveBloqueadaParaApi =>
      codigoErro == 'API_KEY_SERVICE_BLOCKED';

  bool get cotaEsgotada =>
      codigoErro == 'RESOURCE_EXHAUSTED' ||
      message.toLowerCase().contains('quota');

  @override
  String toString() =>
      cause != null ? '$message ($cause)' : message;
}

/// Integracao com Google Gemini para padronizacao de cadastro de produtos.
class GeminiService {
  GeminiService({String? apiKey, List<String>? modelos})
      : _apiKeyOverride = apiKey,
        _modelos = modelos ?? _modelosGemini;

  final String? _apiKeyOverride;
  final List<String> _modelos;

  Future<String> _resolvedApiKey() async {
    final override = _apiKeyOverride?.trim() ?? '';
    if (override.isNotEmpty) {
      return override;
    }
    return GeminiConfig.resolverChave();
  }

  static final Schema _schemaProdutoPadronizado = Schema.object(
    description: 'Produto de material de construcao padronizado',
    properties: {
      'nome_padronizado': Schema.string(
        description:
            'Nome comercial claro e corrigido para catalogo e NFC-e.',
        nullable: false,
      ),
      'categoria_sugerida': Schema.enumString(
        enumValues: ProdutoPadronizadoGemini.categoriasPermitidas,
        description: 'Departamento sugerido na loja.',
        nullable: false,
      ),
      'subcategoria_sugerida': Schema.string(
        description:
            'Subtipo do produto na categoria (texto exato do catalogo quando fornecido).',
        nullable: false,
      ),
      'unidade_medida': Schema.enumString(
        enumValues: ProdutoPadronizadoGemini.unidadesPermitidas,
        description: 'Unidade de venda (UN, KG, MT, etc.).',
        nullable: false,
      ),
      'ncm': Schema.string(
        description: 'NCM 8 digitos ou string vazia.',
        nullable: true,
      ),
      'cest': Schema.string(
        description: 'CEST 7 digitos ou string vazia.',
        nullable: true,
      ),
      'grupo_tributario': Schema.enumString(
        enumValues: ProdutoPadronizadoGemini.gruposTributariosPermitidos,
        description: 'Grupo tributario para NFC-e.',
        nullable: true,
      ),
      'codigo_barras': Schema.string(
        description: 'GTIN/EAN apenas se citado no texto; vazio se nao houver.',
        nullable: true,
      ),
    },
    requiredProperties: [
      'nome_padronizado',
      'categoria_sugerida',
      'subcategoria_sugerida',
      'unidade_medida',
    ],
  );

  Future<bool> get configurado async {
    final k = await _resolvedApiKey();
    return GeminiConfig.chavePareceValida(k);
  }

  /// Padroniza [nomeBruto] via Gemini com Structured Output (JSON).
  ///
  /// Retorna `null` se [nomeBruto] estiver vazio.
  /// Lanca [GeminiConfigException] se a API key nao estiver configurada.
  Future<Map<String, dynamic>?> padronizarProduto(
    String nomeBruto, {
    String? catalogoSubcategorias,
  }) async {
    final bruto = nomeBruto.trim();
    if (bruto.isEmpty) return null;

    final apiKey = await _resolvedApiKey();
    if (!GeminiConfig.chavePareceValida(apiKey)) {
      throw GeminiConfigException(
        'Chave da API Gemini nao configurada. Defina a variavel de ambiente '
        'GEMINI_API_KEY, use --dart-define=GEMINI_API_KEY=... na compilacao '
        'ou salve em Configuracoes > Integracoes.',
      );
    }

    final catalogo = catalogoSubcategorias?.trim() ?? '';
    final promptUsuario = StringBuffer();
    if (catalogo.isNotEmpty) {
      promptUsuario.writeln(catalogo);
      promptUsuario.writeln();
    }
    promptUsuario.writeln(
      'Padronize o seguinte produto de material de construcao:',
    );
    promptUsuario.writeln();
    promptUsuario.write(bruto);

    GenerativeAIException? ultimoErroGemini;

    for (final nomeModelo in _modelos) {
      final model = GenerativeModel(
        model: nomeModelo,
        apiKey: apiKey,
        systemInstruction: Content.system(_systemPrompt),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _schemaProdutoPadronizado,
          temperature: 0.2,
          maxOutputTokens: 768,
        ),
      );

      try {
        final response = await model.generateContent([
          Content.text(promptUsuario.toString()),
        ]);

        final texto = response.text?.trim();
        if (texto == null || texto.isEmpty) {
          return null;
        }

        final decoded = jsonDecode(texto);
        if (decoded is! Map<String, dynamic>) {
          throw GeminiServiceException(
            'Resposta do Gemini em formato inesperado.',
          );
        }

        final padronizado = ProdutoPadronizadoGemini.fromMap(decoded);
        return padronizado.toMap();
      } on GenerativeAIException catch (e) {
        ultimoErroGemini = e;
        final interpretado = _interpretarErroGemini(e);
        if (interpretado.chaveBloqueadaParaApi) {
          throw interpretado;
        }
        // Cota esgotada em um modelo: tenta o proximo (cotas sao por modelo).
        if (nomeModelo != _modelos.last) {
          continue;
        }
        throw interpretado;
      } on FormatException catch (e) {
        throw GeminiServiceException(
          'JSON invalido retornado pelo Gemini: ${e.message}',
          cause: e,
        );
      } catch (e) {
        if (e is GeminiConfigException || e is GeminiServiceException) {
          rethrow;
        }
        throw GeminiServiceException('Erro ao padronizar produto: $e', cause: e);
      }
    }

    final erroGemini = ultimoErroGemini;
    if (erroGemini != null) {
      throw _interpretarErroGemini(erroGemini);
    }
    return null;
  }

  /// Mesmo fluxo de [padronizarProduto], retornando o model tipado.
  Future<ProdutoPadronizadoGemini?> padronizarProdutoModel(
    String nomeBruto, {
    String? catalogoSubcategorias,
  }) async {
    final map = await padronizarProduto(
      nomeBruto,
      catalogoSubcategorias: catalogoSubcategorias,
    );
    if (map == null) return null;
    return ProdutoPadronizadoGemini.fromMap(map);
  }

  static final Schema _schemaQueryBuscaPreco = Schema.object(
    description: 'Query melhorada para busca de preco de mercado',
    properties: {
      'query_busca': Schema.string(
        description:
            'Termo de busca curto e preciso (marca, tipo, medida/peso). '
            'Sem inventar valores de preco.',
        nullable: false,
      ),
      'dica': Schema.string(
        description:
            'Dica curta em portugues sobre o que observar na comparacao '
            '(unidade, embalagem). Nao invente precos numericos.',
        nullable: true,
      ),
    },
    requiredProperties: ['query_busca'],
  );

  /// Sugere query de busca de mercado (gasta 1 request da cota Gemini).
  ///
  /// Nao devolve precos — apenas melhora o termo de pesquisa.
  Future<PrecoMercadoQueryAvancada?> sugerirQueryBuscaPreco(
    String nomeBruto, {
    String unidade = '',
    String codigoBarras = '',
    String cidade = 'Salvador',
    String uf = 'BA',
    List<String> lojasAlvo = const [
      'Ferreira Costa',
      'Leroy Merlin',
      'Mercado Livre',
    ],
  }) async {
    final bruto = nomeBruto.trim();
    if (bruto.isEmpty) return null;

    final apiKey = await _resolvedApiKey();
    if (!GeminiConfig.chavePareceValida(apiKey)) {
      throw GeminiConfigException(
        'Chave da API Gemini nao configurada. '
        'Salve em Configuracoes > Integracoes ou use GEMINI_API_KEY.',
      );
    }

    final lojas = lojasAlvo.where((l) => l.trim().isNotEmpty).join(', ');
    final prompt = StringBuffer()
      ..writeln(
        'Voce ajuda uma loja de materiais de construcao em $cidade/$uf '
        'a buscar precos de mercado na internet.',
      )
      ..writeln(
        'Priorize ofertas dessas redes/sites: $lojas.',
      )
      ..writeln(
        'Monte um termo de busca OBJETIVO (em portugues) para achar ofertas '
        'do mesmo produto nessa regiao. Inclua marca/tipo/medida quando der.',
      )
      ..writeln(
        'Pode mencionar a cidade ($cidade) no termo se ajudar. '
        'NUNCA invente nem sugira valores numericos de preco.',
      )
      ..writeln()
      ..writeln('Produto: $bruto');
    if (unidade.trim().isNotEmpty) {
      prompt.writeln('Unidade de venda: ${unidade.trim()}');
    }
    if (codigoBarras.trim().isNotEmpty) {
      prompt.writeln('Codigo de barras: ${codigoBarras.trim()}');
    }

    GenerativeAIException? ultimoErroGemini;
    for (final nomeModelo in _modelos) {
      final model = GenerativeModel(
        model: nomeModelo,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _schemaQueryBuscaPreco,
          temperature: 0.2,
          maxOutputTokens: 256,
        ),
      );
      try {
        final response = await model.generateContent([
          Content.text(prompt.toString()),
        ]);
        final texto = response.text?.trim();
        if (texto == null || texto.isEmpty) return null;
        final decoded = jsonDecode(texto);
        if (decoded is! Map<String, dynamic>) {
          throw GeminiServiceException(
            'Resposta do Gemini em formato inesperado.',
          );
        }
        return PrecoMercadoQueryAvancada.fromMap(decoded);
      } on GenerativeAIException catch (e) {
        ultimoErroGemini = e;
        final interpretado = _interpretarErroGemini(e);
        if (interpretado.chaveBloqueadaParaApi) throw interpretado;
        if (nomeModelo != _modelos.last) continue;
        throw interpretado;
      } on FormatException catch (e) {
        throw GeminiServiceException(
          'JSON invalido retornado pelo Gemini: ${e.message}',
          cause: e,
        );
      } catch (e) {
        if (e is GeminiConfigException || e is GeminiServiceException) {
          rethrow;
        }
        throw GeminiServiceException(
          'Erro ao sugerir busca de preco: $e',
          cause: e,
        );
      }
    }

    final erroGemini = ultimoErroGemini;
    if (erroGemini != null) throw _interpretarErroGemini(erroGemini);
    return null;
  }

  static GeminiServiceException _interpretarErroGemini(GenerativeAIException e) {
    final msg = e.message;
    final lower = msg.toLowerCase();

    if (lower.contains('blocked') ||
        lower.contains('api_key_service_blocked')) {
      return GeminiServiceException(
        'Chave bloqueada para a API Gemini (Generative Language).',
        cause: e,
        codigoErro: 'API_KEY_SERVICE_BLOCKED',
        instrucoesCorrecao: const [
          'Use uma chave criada em aistudio.google.com/apikey (recomendado), '
          'diferente da chave do Google Custom Search.',
          'Se usar a mesma chave no Google Cloud Console: Credenciais → '
          'sua API Key → Restricoes de API → inclua "Generative Language API".',
          'Ative a API em: console.cloud.google.com/apis/library/'
          'generativelanguage.googleapis.com',
          'Em Restricoes de aplicativo, use "Nenhuma" para app Windows/desktop '
          'ou restrinja por IP — nao use "Sites HTTP" nem apps Android/iOS.',
          'Configure GEMINI_API_KEY e reinicie o app.',
        ],
      );
    }

    if (lower.contains('quota') ||
        lower.contains('resource_exhausted') ||
        lower.contains('rate limit')) {
      return GeminiServiceException(
        'Cota gratuita esgotada em todos os modelos testados. '
        'Aguarde alguns minutos e tente de novo.',
        cause: e,
        codigoErro: 'RESOURCE_EXHAUSTED',
        instrucoesCorrecao: const [
          'O tier gratuito tem limite por minuto e por dia (varia por modelo).',
          'Verifique uso em: ai.dev/rate-limit',
          'Se precisar de mais volume, ative faturamento no Google AI Studio.',
        ],
      );
    }

    return GeminiServiceException(
      'Falha na API Gemini: $msg',
      cause: e,
    );
  }
}

import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../domain/gemini_produto_padronizado.dart';
import '../domain/preco_mercado_resultado.dart';
import 'gemini_config.dart';

/// Modelos em ordem.
///
/// Cotas free sao **por modelo** (RPD/RPM separados). O painel do AI Studio
/// mostra frequentemente `gemini-1.5-flash` com cota restante enquanto 2.5
/// ja esta esgotado — por isso 1.5 vem primeiro.
const List<String> _modelosGemini = [
  'gemini-1.5-flash',
  'gemini-2.0-flash',
  'gemini-2.5-flash-lite',
  'gemini-2.5-flash',
];

/// Ultimo modelo que respondeu OK nesta sessao (evita bater em modelo esgotado).
String? _ultimoModeloGeminiOk;

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
      codigoErro == 'API_KEY_SERVICE_BLOCKED' ||
      codigoErro == 'API_KEY_LEAKED';

  bool get chaveVazada => codigoErro == 'API_KEY_LEAKED';

  bool get cotaEsgotada =>
      codigoErro == 'RESOURCE_EXHAUSTED' ||
      message.toLowerCase().contains('quota') ||
      message.toLowerCase().contains('rate limit');

  bool get modeloIndisponivel => codigoErro == 'MODEL_UNAVAILABLE';

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

  /// Ordem: ultimo que funcionou, depois o restante (lite primeiro).
  List<String> get _modelosOrdemTentativa {
    final preferido = _ultimoModeloGeminiOk?.trim() ?? '';
    if (preferido.isEmpty || !_modelos.contains(preferido)) {
      return List<String>.from(_modelos);
    }
    return [
      preferido,
      for (final m in _modelos)
        if (m != preferido) m,
    ];
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
    final modelos = _modelosOrdemTentativa;

    for (var i = 0; i < modelos.length; i++) {
      final nomeModelo = modelos[i];
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
        _ultimoModeloGeminiOk = nomeModelo;
        return padronizado.toMap();
      } on GenerativeAIException catch (e) {
        ultimoErroGemini = e;
        final interpretado = _interpretarErroGemini(e, modelo: nomeModelo);
        if (interpretado.chaveBloqueadaParaApi) {
          throw interpretado;
        }
        // Se o modelo “preferido” esgotou, limpa para a proxima chamada
        // comecar no 1.5 Flash (lista padrao).
        if (interpretado.cotaEsgotada &&
            _ultimoModeloGeminiOk == nomeModelo) {
          _ultimoModeloGeminiOk = null;
        }
        // Cota e por modelo: se 2.5 esgotou, 1.5 Flash ainda pode ter RPD.
        if (i < modelos.length - 1) {
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
    final modelos = _modelosOrdemTentativa;
    for (var i = 0; i < modelos.length; i++) {
      final nomeModelo = modelos[i];
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
        _ultimoModeloGeminiOk = nomeModelo;
        return PrecoMercadoQueryAvancada.fromMap(decoded);
      } on GenerativeAIException catch (e) {
        ultimoErroGemini = e;
        final interpretado = _interpretarErroGemini(e, modelo: nomeModelo);
        if (interpretado.chaveBloqueadaParaApi) throw interpretado;
        if (interpretado.cotaEsgotada &&
            _ultimoModeloGeminiOk == nomeModelo) {
          _ultimoModeloGeminiOk = null;
        }
        // Cota e por modelo — tenta o proximo (ex.: 1.5 Flash ainda livre).
        if (i < modelos.length - 1) continue;
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

  static GeminiServiceException _interpretarErroGemini(
    GenerativeAIException e, {
    String? modelo,
  }) {
    final msg = e.message;
    final lower = msg.toLowerCase();
    final rotuloModelo = (modelo ?? '').trim().isEmpty
        ? 'Gemini'
        : modelo!.trim();

    if (lower.contains('leaked') ||
        lower.contains('reported as leaked')) {
      return GeminiServiceException(
        'Sua chave da API Gemini foi marcada como vazada pelo Google '
        'e nao pode mais ser usada.',
        cause: e,
        codigoErro: 'API_KEY_LEAKED',
        instrucoesCorrecao: const [
          'Abra aistudio.google.com/apikey e delete/revogue a chave antiga.',
          'Crie uma chave NOVA (nao reutilize a que vazou).',
          'No sistema: Configuracoes → Integracoes → cole a chave nova → '
          'Salvar chave Gemini.',
          'Nunca publique a chave no GitHub, print, WhatsApp ou codigo-fonte. '
          'Se ela ja apareceu em algum lugar, o Google bloqueia automaticamente.',
        ],
      );
    }

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

    if (lower.contains('not found') ||
        lower.contains('is not found') ||
        lower.contains('not supported') ||
        (lower.contains('404') && lower.contains('model'))) {
      return GeminiServiceException(
        'Modelo $rotuloModelo indisponivel nesta chave/projeto.',
        cause: e,
        codigoErro: 'MODEL_UNAVAILABLE',
        instrucoesCorrecao: const [
          'O app tenta outro modelo automaticamente quando este nao existe.',
          'Confira modelos liberados em aistudio.google.com.',
        ],
      );
    }

    if (lower.contains('quota') ||
        lower.contains('resource_exhausted') ||
        lower.contains('rate limit') ||
        lower.contains('429')) {
      final porMinuto = lower.contains('per minute') ||
          lower.contains('rpm') ||
          lower.contains('minute');
      return GeminiServiceException(
        porMinuto
            ? 'Limite por minuto atingido no modelo $rotuloModelo. '
                'Aguarde 1–2 minutos e tente de novo.'
            : 'Cota do modelo $rotuloModelo esgotada (ou indisponivel). '
                'O app tenta outros modelos automaticamente; se todos falharem, '
                'veja o filtro no AI Studio (muitas vezes sobra cota no 1.5 Flash).',
        cause: e,
        codigoErro: 'RESOURCE_EXHAUSTED',
        instrucoesCorrecao: const [
          'No painel Rate limit, mude o filtro do modelo (ex.: Gemini 1.5 Flash). '
          'Cada modelo tem RPM/RPD proprio — 4/20 no 1.5 Flash ainda permite uso.',
          'Limite por minuto bloqueia mesmo com pouco uso no dia: espere ~1 minuto.',
          'Limite diario renova a meia-noite (Pacifico), ~4h–5h da manha no Brasil.',
          'Reinicie o app apos atualizar para usar gemini-1.5-flash primeiro.',
          'Criar outra chave no MESMO projeto nao aumenta a cota.',
        ],
      );
    }

    return GeminiServiceException(
      'Falha na API Gemini: $msg',
      cause: e,
    );
  }
}

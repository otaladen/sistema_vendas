import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../services/gemini_config.dart';
import '../services/gemini_service.dart';
import 'obra_calculadora.dart';

/// Interpretacao de frase livre via Gemini (somente estrutura; quantidades locais).
abstract final class ObraCalculadoraGeminiParse {
  ObraCalculadoraGeminiParse._();

  static final Schema _schema = Schema.object(
    description: 'Parametros de calculo de obra extraidos do texto do vendedor',
    properties: {
      'tipo': Schema.enumString(
        enumValues: ObraReceitaTipo.values.map((t) => t.name).toList(),
        description: 'Tipo de receita: parede, reboco, piso, contrapiso, laje, fundacao ou telhado',
        nullable: false,
      ),
      'largura_m': Schema.number(
        description: 'Largura em metros quando informada',
        nullable: true,
      ),
      'altura_m': Schema.number(
        description: 'Altura em metros quando informada',
        nullable: true,
      ),
      'area_m2': Schema.number(
        description: 'Area em m² quando informada diretamente',
        nullable: true,
      ),
      'tijolo': Schema.string(
        description: 'Medidas do tijolo ex.: 9x19x19',
        nullable: true,
      ),
      'portas': Schema.integer(
        description: 'Quantidade de portas padrao a descontar',
        nullable: true,
      ),
      'janelas': Schema.integer(
        description: 'Quantidade de janelas padrao a descontar',
        nullable: true,
      ),
      'espessura_mm': Schema.number(
        description: 'Espessura em mm para reboco/contrapiso',
        nullable: true,
      ),
    },
    requiredProperties: ['tipo'],
  );

  static Future<ObraCalculadoraParseResult?> interpretar(
    String texto, {
    String? apiKeyOverride,
    double perdaPadraoPct = 10,
  }) async {
    final bruto = texto.trim();
    if (bruto.isEmpty) return null;

    final apiKey = apiKeyOverride?.trim().isNotEmpty == true
        ? apiKeyOverride!.trim()
        : await GeminiConfig.resolverChave();
    if (!GeminiConfig.chavePareceValida(apiKey)) {
      throw GeminiConfigException(
        'Chave Gemini nao configurada para interpretar a obra.',
      );
    }

    const modelos = ['gemini-2.5-flash-lite', 'gemini-2.0-flash'];
    Object? lastError;

    for (final modelo in modelos) {
      try {
        final model = GenerativeModel(
          model: modelo,
          apiKey: apiKey,
          systemInstruction: Content.system('''
Voce extrai parametros de obra para loja de material de construcao.
NUNCA calcule quantidades de materiais — apenas dimensoes e tipo.
Tipos: parede (alvenaria/muro), reboco, piso (ceramica/porcelanato), contrapiso.
Portas e janelas: conte quantidades mencionadas para desconto em parede.
Responda somente JSON conforme schema.
'''),
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _schema,
            temperature: 0.1,
          ),
        );
        final response = await model.generateContent([
          Content.text('Texto do vendedor: $bruto'),
        ]);
        final raw = response.text?.trim();
        if (raw == null || raw.isEmpty) continue;
        final map = jsonDecode(raw);
        if (map is! Map<String, dynamic>) continue;
        return _mapParaResultado(map, perdaPadraoPct: perdaPadraoPct);
      } catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) {
      throw GeminiServiceException(
        'Nao foi possivel interpretar a obra com Gemini.',
        cause: lastError,
      );
    }
    return null;
  }

  static ObraCalculadoraParseResult? _mapParaResultado(
    Map<String, dynamic> m, {
    required double perdaPadraoPct,
  }) {
    final tipo = ObraReceitaTipo.values.firstWhere(
      (t) => t.name == m['tipo']?.toString(),
      orElse: () => ObraReceitaTipo.parede,
    );
    final largura = (m['largura_m'] as num?)?.toDouble();
    final altura = (m['altura_m'] as num?)?.toDouble();
    var area = (m['area_m2'] as num?)?.toDouble() ?? 0;
    if (area <= 0 && largura != null && altura != null && largura > 0 && altura > 0) {
      area = largura * altura;
    }
    final aberturas = <ObraAberturaPadrao>[];
    final portas = (m['portas'] as num?)?.toInt() ?? 0;
    final janelas = (m['janelas'] as num?)?.toInt() ?? 0;
    if (portas > 0) {
      aberturas.add(ObraAberturaPadrao.porta(quantidade: portas));
    }
    if (janelas > 0) {
      aberturas.add(ObraAberturaPadrao.janela(quantidade: janelas));
    }
    final tijoloRaw = m['tijolo']?.toString() ?? '';
    final tipoTijolo =
        ObraCalculadora.detectarTipoTijoloPorTexto(tijoloRaw) ??
            TipoTijoloObra.ceramico8f_9x19x19;
    final espessura = (m['espessura_mm'] as num?)?.toDouble() ?? 20;

    return ObraCalculadoraParseResult(
      tipo: tipo,
      larguraM: largura ?? (area > 0 && altura == null ? 0 : 4),
      alturaM: altura ?? (area > 0 && largura == null ? 0 : 3),
      areaM2: area,
      tipoTijolo: tipoTijolo,
      perdaPct: perdaPadraoPct,
      espessuraMm: espessura,
      aberturas: aberturas,
    );
  }
}

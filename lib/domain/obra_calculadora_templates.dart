import 'dart:convert';

import 'obra_calculadora.dart';

/// Template salvo da calculadora de obra (Configuracoes > PDV).
class ObraCalculadoraTemplate {
  const ObraCalculadoraTemplate({
    required this.id,
    required this.nome,
    required this.tipo,
    this.larguraM = 4,
    this.alturaM = 3,
    this.areaM2 = 0,
    this.tipoTijolo = TipoTijoloObra.ceramico8f_9x19x19,
    this.perdaPct = 10,
    this.espessuraMm = 20,
    this.aberturas = const [],
  });

  final String id;
  final String nome;
  final ObraReceitaTipo tipo;
  final double larguraM;
  final double alturaM;

  /// Quando > 0, usa area direta (piso/contrapiso/reboco em m²).
  final double areaM2;
  final TipoTijoloObra tipoTijolo;
  final double perdaPct;
  final double espessuraMm;
  final List<ObraAberturaPadrao> aberturas;

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'tipo': tipo.name,
        'larguraM': larguraM,
        'alturaM': alturaM,
        'areaM2': areaM2,
        'tipoTijolo': tipoTijolo.name,
        'perdaPct': perdaPct,
        'espessuraMm': espessuraMm,
        'aberturas': aberturas.map((a) => a.toMap()).toList(),
      };

  factory ObraCalculadoraTemplate.fromMap(Map<String, dynamic> m) {
    return ObraCalculadoraTemplate(
      id: (m['id'] ?? '').toString(),
      nome: (m['nome'] ?? 'Template').toString(),
      tipo: ObraReceitaTipo.values.firstWhere(
        (t) => t.name == m['tipo'],
        orElse: () => ObraReceitaTipo.parede,
      ),
      larguraM: (m['larguraM'] as num?)?.toDouble() ?? 4,
      alturaM: (m['alturaM'] as num?)?.toDouble() ?? 3,
      areaM2: (m['areaM2'] as num?)?.toDouble() ?? 0,
      tipoTijolo: TipoTijoloObra.values.firstWhere(
        (t) => t.name == m['tipoTijolo'],
        orElse: () => TipoTijoloObra.ceramico8f_9x19x19,
      ),
      perdaPct: (m['perdaPct'] as num?)?.toDouble() ?? 10,
      espessuraMm: (m['espessuraMm'] as num?)?.toDouble() ?? 20,
      aberturas: (m['aberturas'] as List?)
              ?.whereType<Map>()
              .map((e) => ObraAberturaPadrao.fromMap(e.cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }
}

abstract final class ObraCalculadoraTemplatesUtil {
  ObraCalculadoraTemplatesUtil._();

  static List<ObraCalculadoraTemplate> decode(String json) {
    if (json.trim().isEmpty || json.trim() == '[]') return [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => ObraCalculadoraTemplate.fromMap(e.cast<String, dynamic>()))
          .where((t) => t.id.isNotEmpty && t.nome.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encode(List<ObraCalculadoraTemplate> lista) =>
      jsonEncode(lista.map((t) => t.toMap()).toList());

  static ObraCalculadoraResultado? calcularTemplate(
    ObraCalculadoraTemplate template, {
    double perdaRebocoPct = 15,
    double perdaPisoPct = 10,
    double perdaContrapisoPct = 10,
    double m2PorCaixaPiso = 1.44,
  }) {
    return ObraCalculadora.calcularDeParse(
      ObraCalculadoraParseResult(
        tipo: template.tipo,
        larguraM: template.larguraM,
        alturaM: template.alturaM,
        areaM2: template.areaM2,
        tipoTijolo: template.tipoTijolo,
        perdaPct: template.perdaPct,
        espessuraMm: template.espessuraMm,
        aberturas: template.aberturas,
      ),
      perdaRebocoPct: perdaRebocoPct,
      perdaPisoPct: perdaPisoPct,
      perdaContrapisoPct: perdaContrapisoPct,
      m2PorCaixaPiso: m2PorCaixaPiso,
    );
  }

  static List<ObraCalculadoraTemplate> padroesLoja() => const [
        ObraCalculadoraTemplate(
          id: 'padrao_parede_sala',
          nome: 'Parede sala 4×3 m',
          tipo: ObraReceitaTipo.parede,
          larguraM: 4,
          alturaM: 3,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_reboco_interno',
          nome: 'Reboco interno 12 m²',
          tipo: ObraReceitaTipo.reboco,
          areaM2: 12,
          espessuraMm: 20,
          perdaPct: 15,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_piso_banheiro',
          nome: 'Piso banheiro 6 m²',
          tipo: ObraReceitaTipo.piso,
          areaM2: 6,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_contrapiso',
          nome: 'Contrapiso 20 m²',
          tipo: ObraReceitaTipo.contrapiso,
          areaM2: 20,
          espessuraMm: 30,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_laje_garagem',
          nome: 'Laje garagem 20 m²',
          tipo: ObraReceitaTipo.laje,
          areaM2: 20,
          espessuraMm: 100,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_fundacao',
          nome: 'Fundacao 10 m linear',
          tipo: ObraReceitaTipo.fundacao,
          larguraM: 10,
          alturaM: 0.40,
          espessuraMm: 500,
        ),
        ObraCalculadoraTemplate(
          id: 'padrao_telhado',
          nome: 'Telhado 40 m²',
          tipo: ObraReceitaTipo.telhado,
          areaM2: 40,
        ),
      ];
}

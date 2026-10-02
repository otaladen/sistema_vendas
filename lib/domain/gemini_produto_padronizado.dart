import 'produto_categorias_catalogo.dart';
import 'produto_unidades_catalogo.dart';

/// Resultado estruturado da padronizacao de produto via Gemini.
class ProdutoPadronizadoGemini {
  const ProdutoPadronizadoGemini({
    required this.nomePadronizado,
    required this.categoriaSugerida,
    required this.subcategoriaSugerida,
    required this.unidadeMedida,
    this.codigoBarras = '',
    this.ncm = '',
    this.cest = '',
    this.grupoTributario = 'tributado',
  });

  final String nomePadronizado;
  final String categoriaSugerida;
  final String subcategoriaSugerida;
  final String unidadeMedida;
  /// GTIN/EAN (8 a 14 digitos) — vazio se desconhecido.
  final String codigoBarras;
  /// NCM com 8 digitos (sem pontuacao).
  final String ncm;
  /// CEST com 7 digitos (sem pontuacao).
  final String cest;
  /// `tributado`, `isento` ou `substituicao_tributaria`.
  final String grupoTributario;

  static final List<String> categoriasPermitidas =
      ProdutoCategoriasCatalogo.materiaisConstrucao.keys.toList(
        growable: false,
      );

  static List<String> get unidadesPermitidas =>
      ProdutoUnidadesCatalogo.unidadesVenda;

  static const gruposTributariosPermitidos = <String>[
    'tributado',
    'isento',
    'substituicao_tributaria',
  ];

  factory ProdutoPadronizadoGemini.fromMap(Map<String, dynamic> map) {
    String s(String key) => (map[key] ?? '').toString().trim();

    var categoria = s('categoria_sugerida');
    if (!categoriasPermitidas.contains(categoria)) {
      categoria = 'Outros';
    }

    final unidade =
        ProdutoUnidadesCatalogo.normalizarUnidadeVenda(s('unidade_medida'));

    final nome = s('nome_padronizado');
    if (nome.isEmpty) {
      throw FormatException('Campo nome_padronizado ausente ou vazio.');
    }

    var ncm = s('ncm').replaceAll(RegExp(r'\D'), '');
    if (ncm.length > 8) ncm = ncm.substring(0, 8);

    var cest = s('cest').replaceAll(RegExp(r'\D'), '');
    if (cest.length > 7) cest = cest.substring(0, 7);

    var codigoBarras = s('codigo_barras').replaceAll(RegExp(r'\D'), '');
    if (codigoBarras.length > 14) {
      codigoBarras = codigoBarras.substring(0, 14);
    }

    var grupo = s('grupo_tributario').toLowerCase();
    if (grupo == 'st' || grupo == 'substituicao tributaria') {
      grupo = 'substituicao_tributaria';
    }
    if (!gruposTributariosPermitidos.contains(grupo)) {
      grupo = 'tributado';
    }

    return ProdutoPadronizadoGemini(
      nomePadronizado: nome,
      categoriaSugerida: categoria,
      subcategoriaSugerida: s('subcategoria_sugerida'),
      unidadeMedida: unidade,
      codigoBarras: codigoBarras,
      ncm: ncm,
      cest: cest,
      grupoTributario: grupo,
    );
  }

  Map<String, dynamic> toMap() => {
        'nome_padronizado': nomePadronizado,
        'categoria_sugerida': categoriaSugerida,
        'subcategoria_sugerida': subcategoriaSugerida,
        'unidade_medida': unidadeMedida,
        'codigo_barras': codigoBarras,
        'ncm': ncm,
        'cest': cest,
        'grupo_tributario': grupoTributario,
      };
}

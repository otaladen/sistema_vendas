import '../model/produto.dart';

/// Regras de elegibilidade para substitutos/similares na consulta PDV.
abstract final class PdvConsultaSimilaresUtil {
  PdvConsultaSimilaresUtil._();

  static const _categoriasGenericas = {
    '',
    'geral',
    'diversos',
    'outros',
    'outro',
    'misc',
    'sem categoria',
    'nao categorizado',
    'nao classificado',
    'nc',
    'na',
    'indefinido',
  };

  static String _norm(String s) => s.trim().toLowerCase();

  /// Categoria util para agrupar substitutos (nao vazia e nao generica).
  static bool categoriaEspecifica(String categoria) {
    final c = _norm(categoria);
    if (c.length < 2) return false;
    return !_categoriasGenericas.contains(c);
  }

  static bool subcategoriaUtil(String subcategoria) =>
      _norm(subcategoria).length >= 2;

  /// Produto selecionado permite buscar similares.
  static bool referenciaElegivel(Produto produto) {
    if (subcategoriaUtil(produto.subcategoria)) return true;
    return categoriaEspecifica(produto.categoria);
  }

  /// Candidato pertence ao mesmo grupo do produto de referencia.
  static bool candidatoCompativel(Produto referencia, Produto candidato) {
    if (candidato.id <= 0 || candidato.id == referencia.id) return false;
    if (candidato.estoqueLivreParaVenda <= 0) return false;

    final subRef = _norm(referencia.subcategoria);
    final subCand = _norm(candidato.subcategoria);

    if (subcategoriaUtil(referencia.subcategoria)) {
      if (subCand != subRef) return false;
      if (categoriaEspecifica(referencia.categoria)) {
        return _norm(candidato.categoria) == _norm(referencia.categoria);
      }
      return true;
    }

    if (!categoriaEspecifica(referencia.categoria)) return false;
    return _norm(candidato.categoria) == _norm(referencia.categoria);
  }
}

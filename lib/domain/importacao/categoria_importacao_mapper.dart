import '../produto_categorias_catalogo.dart';

class CategoriaImportacaoResult {
  const CategoriaImportacaoResult({
    required this.categoria,
    required this.subcategoria,
  });

  final String categoria;
  final String subcategoria;
}

/// Mapeia familia/grupo/subgrupo de sistemas legados para o catalogo da loja.
abstract final class CategoriaImportacaoMapper {
  CategoriaImportacaoMapper._();

  static const _genericos = <String>{
    'diversos',
    'geral',
    'semcategoria',
    'naoclassificado',
    'outros',
    'importacao',
  };

  static const _aliasesCategoria = <String, String>{
    'hidraulica': 'Hidraulica',
    'hidraulico': 'Hidraulica',
    'eletrica': 'Eletrica',
    'eletrico': 'Eletrica',
    'ferragens': 'Ferragens',
    'ferramentas': 'Ferramentas',
    'tintas': 'Tintas e Acessorios',
    'tintaseacessorios': 'Tintas e Acessorios',
    'cimento': 'Cimento e Argamassas',
    'cimentoeargamassas': 'Cimento e Argamassas',
    'argamassa': 'Cimento e Argamassas',
    'telhas': 'Telhas e Cobertura',
    'telhasecobertura': 'Telhas e Cobertura',
    'cobertura': 'Telhas e Cobertura',
    'alvenaria': 'Estrutural e Alvenaria',
    'estrutural': 'Estrutural e Alvenaria',
    'estruturalealvenaria': 'Estrutural e Alvenaria',
    'madeiras': 'Madeiras e Chapas',
    'madeirasechapas': 'Madeiras e Chapas',
    'pisos': 'Pisos e Revestimentos',
    'pisoserevestimentos': 'Pisos e Revestimentos',
    'revestimentos': 'Pisos e Revestimentos',
    'loucas': 'Loucas e Metais',
    'loucasemetais': 'Loucas e Metais',
    'metais': 'Loucas e Metais',
    'impermeabilizacao': 'Impermeabilizacao e Quimicos',
    'impermeabilizacaoequimicos': 'Impermeabilizacao e Quimicos',
    'quimicos': 'Impermeabilizacao e Quimicos',
    'jardinagem': 'Jardinagem e Externo',
    'jardinagemeexterno': 'Jardinagem e Externo',
    'forros': 'Forros e Divisorias',
    'forrosedivisorias': 'Forros e Divisorias',
    'drywall': 'Forros e Divisorias',
  };

  static CategoriaImportacaoResult resolver({
    String familia = '',
    String grupo = '',
    String subgrupo = '',
    String subcategoriaFallback = 'Importacao legado',
  }) {
    final f = _limparLegado(familia);
    final g = _limparLegado(grupo);
    final sg = _limparLegado(subgrupo);

    for (final candidato in [g, f, sg]) {
      if (candidato.isEmpty) continue;
      final alias = _aliasesCategoria[_norm(candidato)];
      if (alias != null && _catalogo.containsKey(alias)) {
        final sub = _resolverSubcategoria(alias, sg) ??
            _resolverSubcategoria(alias, g) ??
            _resolverSubcategoria(alias, f);
        return CategoriaImportacaoResult(
          categoria: alias,
          subcategoria: sub ?? _subcategoriaLivre(sg, g, f, subcategoriaFallback),
        );
      }
    }

    for (final cat in _catalogo.keys) {
      if (cat == ProdutoCategoriasCatalogo.outros) continue;
      if (_match(g, cat) || _match(f, cat)) {
        final sub = _resolverSubcategoria(cat, sg) ??
            _resolverSubcategoria(cat, g) ??
            _resolverSubcategoria(cat, f);
        return CategoriaImportacaoResult(
          categoria: cat,
          subcategoria: sub ?? _subcategoriaLivre(sg, g, f, subcategoriaFallback),
        );
      }
    }

    for (final entry in _catalogo.entries) {
      if (entry.key == ProdutoCategoriasCatalogo.outros) continue;
      for (final sub in entry.value) {
        if (_match(sg, sub) || _match(g, sub) || _match(f, sub)) {
          return CategoriaImportacaoResult(
            categoria: entry.key,
            subcategoria: sub,
          );
        }
      }
    }

    final porPalavra = _porPalavrasChave('$g $f $sg');
    if (porPalavra != null) {
      return porPalavra;
    }

    if (g.isNotEmpty) {
      return CategoriaImportacaoResult(
        categoria: ProdutoCategoriasCatalogo.outros,
        subcategoria: sg.isNotEmpty ? '$g / $sg' : g,
      );
    }
    if (f.isNotEmpty) {
      return CategoriaImportacaoResult(
        categoria: ProdutoCategoriasCatalogo.outros,
        subcategoria: sg.isNotEmpty ? '$f / $sg' : f,
      );
    }
    if (sg.isNotEmpty) {
      return CategoriaImportacaoResult(
        categoria: ProdutoCategoriasCatalogo.outros,
        subcategoria: sg,
      );
    }

    return CategoriaImportacaoResult(
      categoria: ProdutoCategoriasCatalogo.outros,
      subcategoria: subcategoriaFallback,
    );
  }

  static Map<String, List<String>> get _catalogo =>
      ProdutoCategoriasCatalogo.materiaisConstrucao;

  static String _limparLegado(String valor) {
    final t = valor.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '';
    if (_genericos.contains(_norm(t))) return '';
    return t;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _match(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  static String? _resolverSubcategoria(String categoria, String sugestao) {
    final s = _limparLegado(sugestao);
    if (s.isEmpty || categoria == ProdutoCategoriasCatalogo.outros) {
      return null;
    }
    final lista = _catalogo[categoria] ?? [];
    if (lista.isEmpty) return null;

    final alvo = _norm(s);
    for (final sub in lista) {
      if (_norm(sub) == alvo) return sub;
    }
    for (final sub in lista) {
      final ns = _norm(sub);
      if (ns.contains(alvo) || alvo.contains(ns)) return sub;
    }

    if (categoria == 'Hidraulica') {
      final t = s.toLowerCase();
      if (t.contains('tubo') ||
          t.contains('conex') ||
          t.contains('pvc') ||
          t.contains('esgoto') ||
          t.contains('cano')) {
        return 'Tubos e Conexoes';
      }
      if (t.contains('torneira') || t.contains('misturador')) {
        return 'Torneiras';
      }
    }

    if (categoria == 'Tintas e Acessorios' && s.toLowerCase().contains('tinta')) {
      return s.toLowerCase().contains('esmalte')
          ? 'Tinta Esmalte'
          : 'Tinta Acrilica';
    }

    if (categoria == 'Cimento e Argamassas') {
      final t = s.toLowerCase();
      if (t.contains('argamassa')) return 'Argamassa';
      if (t.contains('cimento')) return 'Cimento';
    }

    return null;
  }

  static String _subcategoriaLivre(
    String subgrupo,
    String grupo,
    String familia,
    String fallback,
  ) {
    if (subgrupo.isNotEmpty) return subgrupo;
    if (grupo.isNotEmpty && grupo != familia) return grupo;
    if (familia.isNotEmpty) return familia;
    return fallback;
  }

  static CategoriaImportacaoResult? _porPalavrasChave(String texto) {
    final t = texto.toLowerCase();
    if (t.trim().isEmpty) return null;

    String? cat;
    if (t.contains('hidraul') ||
        t.contains('tubo') ||
        t.contains('cano') ||
        t.contains('registro') ||
        t.contains('caixa d')) {
      cat = 'Hidraulica';
    } else if (t.contains('eletric') ||
        t.contains('fio') ||
        t.contains('cabo') ||
        t.contains('disjuntor') ||
        t.contains('tomada')) {
      cat = 'Eletrica';
    } else if (t.contains('tinta') ||
        t.contains('verniz') ||
        t.contains('selador') ||
        t.contains('pincel') ||
        t.contains('rolo')) {
      cat = 'Tintas e Acessorios';
    } else if (t.contains('cimento') ||
        t.contains('argamassa') ||
        t.contains('rejunte')) {
      cat = 'Cimento e Argamassas';
    } else if (t.contains('telha') ||
        t.contains('cumeeira') ||
        t.contains('calha') ||
        t.contains('rufo')) {
      cat = 'Telhas e Cobertura';
    } else if (t.contains('tijolo') ||
        t.contains('bloco') ||
        t.contains('areia') ||
        t.contains('brita') ||
        t.contains('vergalhao')) {
      cat = 'Estrutural e Alvenaria';
    } else if (t.contains('parafuso') ||
        t.contains('prego') ||
        t.contains('fechadura') ||
        t.contains('dobradica')) {
      cat = 'Ferragens';
    } else if (t.contains('mdf') ||
        t.contains('compensado') ||
        t.contains('madeira') ||
        t.contains('osb')) {
      cat = 'Madeiras e Chapas';
    } else if (t.contains('porcelanato') ||
        t.contains('ceramico') ||
        t.contains('revestimento') ||
        t.contains('rodape')) {
      cat = 'Pisos e Revestimentos';
    } else if (t.contains('vaso') ||
        t.contains('lavatorio') ||
        t.contains('chuveiro') ||
        t.contains('cuba')) {
      cat = 'Loucas e Metais';
    } else if (t.contains('impermeab') ||
        t.contains('silicone') ||
        t.contains('vedante')) {
      cat = 'Impermeabilizacao e Quimicos';
    } else if (t.contains('ferramenta') || t.contains('epi')) {
      cat = 'Ferramentas';
    } else if (t.contains('mangueira') || t.contains('jardim')) {
      cat = 'Jardinagem e Externo';
    } else if (t.contains('drywall') ||
        t.contains('forro') ||
        t.contains('gesso')) {
      cat = 'Forros e Divisorias';
    }

    if (cat == null) return null;
    final sub = _resolverSubcategoria(cat, texto) ?? texto.trim();
    return CategoriaImportacaoResult(
      categoria: cat,
      subcategoria: sub.isEmpty ? 'Importacao legado' : sub,
    );
  }
}

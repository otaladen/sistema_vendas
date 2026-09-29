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
      final alias = ProdutoCategoriasCatalogo.resolverCategoria(candidato);
      if (alias != null && alias != ProdutoCategoriasCatalogo.outros) {
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

    final porSubExata = _buscarPorSubcategoria(f, g, sg, exata: true);
    if (porSubExata != null) return porSubExata;

    final porSub = _buscarPorSubcategoria(f, g, sg, exata: false);
    if (porSub != null) return porSub;

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

  static String _norm(String s) => ProdutoCategoriasCatalogo.normalizar(s);

  static CategoriaImportacaoResult? _buscarPorSubcategoria(
    String familia,
    String grupo,
    String subgrupo, {
    required bool exata,
  }) {
    CategoriaImportacaoResult? melhor;
    var melhorScore = -1.0;
    for (final entry in _catalogo.entries) {
      if (entry.key == ProdutoCategoriasCatalogo.outros) continue;
      for (final sub in entry.value) {
        for (final candidato in [subgrupo, grupo, familia]) {
          if (candidato.isEmpty) continue;
          final score = _scoreSub(candidato, sub, exata: exata);
          if (score <= melhorScore) continue;
          melhorScore = score;
          melhor = CategoriaImportacaoResult(
            categoria: entry.key,
            subcategoria: sub,
          );
        }
      }
    }
    return melhor;
  }

  /// 1 em igualdade. Em aproximacao, so aceita textos bem proximos
  /// para nao puxar "Gesso" para "Gesso em Po" nem "Cola" para "Argamassa Colante".
  static double _scoreSub(String a, String b, {required bool exata}) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return -1;
    if (na == nb) return exata ? 1 : -1;
    if (exata) return -1;
    if (!na.contains(nb) && !nb.contains(na)) return -1;
    final menor = na.length < nb.length ? na.length : nb.length;
    final maior = na.length > nb.length ? na.length : nb.length;
    final ratio = menor / maior;
    if (ratio < 0.72) return -1;
    return ratio;
  }

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
    } else if (t.contains('ferramenta')) {
      cat = 'Ferramentas';
    } else if (t.contains('mangueira') || t.contains('jardim')) {
      cat = 'Jardinagem e Externo';
    } else if (t.contains('drywall') ||
        t.contains('forro') ||
        t.contains('gesso')) {
      cat = 'Forros e Divisorias';
    } else if (t.contains('lampada') ||
        t.contains('refletor') ||
        t.contains('plafon') ||
        t.contains('fita de led') ||
        t.contains('spot')) {
      cat = 'Iluminacao';
    } else if (t.contains('ventilador') ||
        t.contains('exaustor') ||
        t.contains('ar condicionado') ||
        t.contains('aquecedor')) {
      cat = 'Climatizacao';
    } else if (t.contains('epi') ||
        t.contains('capacete') ||
        t.contains('respirador') ||
        t.contains('bota de seguranca') ||
        t.contains('protetor auricular')) {
      cat = 'EPIs e Seguranca';
    } else if (t.contains('lixa') ||
        t.contains('disco de corte') ||
        t.contains('broca') ||
        t.contains('serra copo') ||
        t.contains('eletrodo')) {
      cat = 'Abrasivos e Corte';
    } else if (t.contains('alambrado') ||
        t.contains('arame farpado') ||
        t.contains('mourao') ||
        t.contains('concertina') ||
        t.contains('tela soldada')) {
      cat = 'Telas, Cercas e Alambrados';
    } else if (t.contains('fita crepe') ||
        t.contains('veda rosca') ||
        t.contains('cola branca') ||
        t.contains('adesivo')) {
      cat = 'Colas, Fitas e Vedacao';
    } else if (t.contains('4x2') || t.contains('4x4')) {
      cat = 'Eletrica';
    } else if (t.contains('porta') ||
        t.contains('janela') ||
        t.contains('vidro') ||
        t.contains('basculante') ||
        t.contains('espelho')) {
      cat = 'Portas, Janelas e Vidros';
    }

    if (cat == null) return null;
    final sub = _resolverSubcategoria(cat, texto) ?? texto.trim();
    return CategoriaImportacaoResult(
      categoria: cat,
      subcategoria: sub.isEmpty ? 'Importacao legado' : sub,
    );
  }
}

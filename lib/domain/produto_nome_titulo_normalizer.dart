/// Converte nomes de produto em titulo legivel (nao tudo MAIUSCULO).
///
/// Ex.: `ABRACADEIRA NYLON 100MM X 2.5MM` → `Abracadeira Nylon 100mm X 2.5mm`
/// Ex.: `Abraçadeira de Nylon 100mm X 2.5mm` permanece coerente.
abstract final class ProdutoNomeTituloNormalizer {
  ProdutoNomeTituloNormalizer._();

  static const _conectores = {
    'de',
    'da',
    'do',
    'das',
    'dos',
    'e',
    'em',
    'com',
    'para',
    'por',
    'p',
    'a',
  };

  /// Unidades / siglas curtas tipicas de material de construcao.
  static const _siglasMaiusculas = {
    'pvc',
    'uv',
    'led',
    'mdf',
    'osb',
    'npt',
    'bsp',
    'dn',
    'pead',
    'cpvc',
    'cnh',
    'rg',
    'cpf',
    'cnpj',
    'nf',
    'nfe',
    'nfce',
  };

  static const _unidadesMinusculas = {
    'kg',
    'g',
    'mg',
    'mm',
    'cm',
    'mt',
    'm',
    'm2',
    'm³',
    'm3',
    'l',
    'lt',
    'ml',
    'w',
    'v',
    'a',
    'un',
    'cx',
    'sc',
    'pct',
    'pc',
  };

  static String normalizar(String nome) {
    final texto = nome.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (texto.isEmpty) return '';

    final tokens = texto.split(' ').where((p) => p.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      out.add(_normalizarToken(tokens[i], indice: i));
    }
    return out.join(' ');
  }

  static String _normalizarToken(String tokenOriginal, {required int indice}) {
    final bruto = tokenOriginal.trim();
    if (bruto.isEmpty) return '';

    // Multiplicador tipico: "X" / "x" sozinho.
    if (bruto.toLowerCase() == 'x') return 'X';

    // Fracao / bitola: 3/4, 1/2 — permanece minuscula nos digitos.
    if (bruto.contains('/') && !_pareceUrl(bruto)) {
      return bruto
          .split('/')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map((p) => _normalizarTokenSimples(p, indice: indice))
          .join('/');
    }

    return _normalizarTokenSimples(bruto, indice: indice);
  }

  static bool _pareceUrl(String s) =>
      s.contains('http') || s.contains('www.');

  static String _normalizarTokenSimples(String bruto, {required int indice}) {
    final lower = bruto.toLowerCase();

    if (_siglasMaiusculas.contains(lower)) {
      return lower.toUpperCase();
    }
    if (_unidadesMinusculas.contains(lower)) {
      return lower;
    }
    if (indice > 0 && _conectores.contains(lower)) {
      return lower;
    }

    // Medidas coladas: 100mm, 2.5mm, 450x7.0mm, 19a25mm
    final medida = _formatarMedida(bruto);
    if (medida != null) return medida;

    // Marca curta toda letra (ex.: BCA) → maiuscula se veio assim e len <= 5
    if (bruto.length <= 5 &&
        RegExp(r'^[A-Za-zÀ-ÿ]+$').hasMatch(bruto) &&
        bruto == bruto.toUpperCase() &&
        bruto.length >= 2 &&
        !_conectores.contains(lower)) {
      // Evita manter ABRAC... (palavras longas). Curtas tipo TIGRE ja viram titulo.
      // So mantem MAIUSCULO se parece sigla (<=3) ou se todas as letras.
      if (bruto.length <= 3) return bruto.toUpperCase();
    }

    if (bruto.isEmpty) return '';
    final inicial = lower[0].toUpperCase();
    final resto = lower.length > 1 ? lower.substring(1) : '';
    return '$inicial$resto';
  }

  /// Retorna formatacao especial se o token parecer medida/dimensao.
  static String? _formatarMedida(String bruto) {
    final lower = bruto.toLowerCase();

    // 100mm / 2.5mm / 7,0mm
    final soMedida = RegExp(
      r'^(\d+[.,]?\d*)(mm|cm|m|mt|kg|g|ml|l|lt|w|v)$',
      caseSensitive: false,
    ).firstMatch(lower);
    if (soMedida != null) {
      return '${soMedida.group(1)}${soMedida.group(2)!.toLowerCase()}';
    }

    // 450x7.0mm / 100x2.5mm / 19a25mm
    final dim = RegExp(
      r'^(\d+[.,]?\d*)([xXaA])(\d+[.,]?\d*)(mm|cm|m|mt)?$',
      caseSensitive: false,
    ).firstMatch(lower);
    if (dim != null) {
      final a = dim.group(1)!;
      final sep = dim.group(2)!.toLowerCase() == 'a' ? 'A' : 'X';
      final b = dim.group(3)!;
      final u = (dim.group(4) ?? '').toLowerCase();
      return '$a$sep$b$u';
    }

    // 3/4x1 ja tratado por fracao + parts; 3/4"
    return null;
  }
}

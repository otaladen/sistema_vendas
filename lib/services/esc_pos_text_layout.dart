/// Quebra de linha e alinhamento em colunas fixas (bobina 48 / 32).
abstract final class EscPosTextLayout {
  EscPosTextLayout._();

  /// Limite recomendado por linha com fonte expandida (dupla largura).
  static const int colunasExpandidasMaxPorLinha = 24;

  static int colunasFonteExpandida(int colsNormais) => colsNormais ~/ 2;

  static int maxCharsTituloExpandido(int colsNormais) {
    final exp = colunasFonteExpandida(colsNormais);
    if (exp <= 0) return 16;
    return colunasExpandidasMaxPorLinha.clamp(16, exp);
  }

  static String trunc(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    if (max <= 1) return t.substring(0, max);
    return '${t.substring(0, max - 1)}.';
  }

  static List<String> wrap(String s, int cols) {
    final t = s.trim();
    if (t.isEmpty) return const [];
    if (cols < 1) return [trunc(t, 1)];
    if (t.length <= cols) return [t];
    final out = <String>[];
    var rest = t;
    while (rest.length > cols) {
      var cut = rest.lastIndexOf(' ', cols);
      if (cut < cols ~/ 2) cut = cols;
      out.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static List<String> wrapTituloExpandido(String s, int colsNormais) =>
      wrap(s, maxCharsTituloExpandido(colsNormais));

  static String padCols(String left, String right, int cols) {
    final l = trunc(left, cols - 1);
    final r = trunc(right, cols - 1);
    final space = cols - l.length - r.length;
    if (space <= 0) return trunc('$l $r', cols);
    return '$l${' ' * space}$r';
  }

  /// Rotulo a esquerda ([padRight] no espaco disponivel) e valor cravado a direita.
  static String rotuloValor(String rotulo, String valor, int cols) {
    final v = valor.trim();
    if (cols < 1) return trunc(v.isEmpty ? rotulo : v, 1);
    if (v.isEmpty) {
      return wrap(rotulo, cols).join('\n');
    }
    if (v.length >= cols) return trunc(v, cols);
    final rotuloMax = cols - v.length;
    if (rotuloMax <= 0) return v.padLeft(cols);
    final r = rotulo.length <= rotuloMax
        ? rotulo.padRight(rotuloMax)
        : trunc(rotulo, rotuloMax);
    return '$r$v';
  }
}

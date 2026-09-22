/// Normalizacao e parsing da busca textual da aba Entregas.
abstract final class EntregaBuscaTexto {
  EntregaBuscaTexto._();

  static final _naoAlfanumerico = RegExp(r'[^\w\s\/\-\+]');

  /// Minusculas, sem acentos e pontuacao irrelevante (contains case-insensitive).
  static String normalizar(String texto) {
    final lower = texto.toLowerCase().trim();
    if (lower.isEmpty) return '';
    final sb = StringBuffer();
    const mapa = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      sb.write(mapa[char] ?? char);
    }
    return sb.toString().replaceAll(_naoAlfanumerico, ' ');
  }

  static bool contem(String texto, String termoNormalizado) {
    if (termoNormalizado.isEmpty) return true;
    final base = normalizar(texto);
    if (base.isEmpty) return false;
    return base.contains(termoNormalizado);
  }

  /// Digitos do termo (#712, 712) para controle / pedido; null se nao for busca numerica.
  static String? digitosControleOuPedido(String termoBruto) {
    var raw = termoBruto.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('#')) raw = raw.substring(1).trim();
    if (raw.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    return raw;
  }
}

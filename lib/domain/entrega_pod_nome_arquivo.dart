/// Validacao de nomes de arquivo POD (cliente + servidor sync).
abstract final class EntregaPodNomeArquivo {
  EntregaPodNomeArquivo._();

  static final RegExp padrao = RegExp(r'^venda_\d+_\d{8}_\d{6}\.jpg$');

  static bool valido(String raw) {
    final name = raw.trim();
    if (name.isEmpty ||
        name.contains('..') ||
        name.contains('\\') ||
        name.contains('/')) {
      return false;
    }
    return padrao.hasMatch(name);
  }

  static String? extrairNomeArquivo(String caminhoOuRelativo) {
    final s = caminhoOuRelativo.trim().replaceAll(r'\', '/');
    if (s.isEmpty) return null;
    final partes = s.split('/');
    final nome = partes.isNotEmpty ? partes.last : s;
    return valido(nome) ? nome : null;
  }
}

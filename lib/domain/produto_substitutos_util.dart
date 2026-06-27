/// Parse e formatacao de substitutos cadastrados no produto.
abstract final class ProdutoSubstitutosUtil {
  ProdutoSubstitutosUtil._();

  static List<int> parseIds(String raw) {
    if (raw.trim().isEmpty) return const [];
    final vistos = <int>{};
    final out = <int>[];
    for (final parte in raw.split(RegExp(r'[;,]'))) {
      final id = int.tryParse(parte.trim()) ?? 0;
      if (id <= 0 || vistos.contains(id)) continue;
      vistos.add(id);
      out.add(id);
    }
    return out;
  }

  static String formatIds(Iterable<int> ids) {
    final vistos = <int>{};
    final out = <String>[];
    for (final id in ids) {
      if (id <= 0 || vistos.contains(id)) continue;
      vistos.add(id);
      out.add('$id');
    }
    return out.join(';');
  }
}

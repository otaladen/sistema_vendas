import '../model/motorista.dart';

/// Lista motoristas a partir de repo local ou API (`dynamic`) sem TypeError no `.where`.
abstract final class MotoristaListaSafe {
  MotoristaListaSafe._();

  static List<Motorista> listarAtivos(dynamic motoristaRepository) {
    if (motoristaRepository == null) return const [];
    try {
      final raw = motoristaRepository.listarAtivos();
      if (raw is List<Motorista>) {
        return List<Motorista>.from(raw);
      }
      if (raw is! Iterable) return const [];
      final out = <Motorista>[];
      for (final m in raw) {
        if (m is Motorista) out.add(m);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static List<String> nomesAtivos(dynamic motoristaRepository) {
    final out = <String>[];
    for (final m in listarAtivos(motoristaRepository)) {
      final n = m.nome.trim();
      if (n.isNotEmpty) out.add(n);
    }
    return out;
  }

  /// Nomes ativos sem duplicata (DropdownButton quebra com value repetido).
  static List<String> nomesAtivosUnicos(dynamic motoristaRepository) {
    final seen = <String>{};
    final out = <String>[];
    for (final n in nomesAtivos(motoristaRepository)) {
      if (seen.add(n.toLowerCase())) out.add(n);
    }
    return out;
  }

  /// Valor seguro para dropdown: casa por trim/case; inclui [atual] se nao
  /// estiver no cadastro (motorista inativo ou so no pedido).
  static List<String> opcoesDropdown({
    required dynamic motoristaRepository,
    String? atual,
  }) {
    final out = nomesAtivosUnicos(motoristaRepository);
    final extra = (atual ?? '').trim();
    if (extra.isEmpty || extra == 'Nao definido') return out;
    final jaTem = out.any((n) => n.toLowerCase() == extra.toLowerCase());
    if (!jaTem) out.insert(0, extra);
    return out;
  }

  static String? valorInicialDropdown({
    required List<String> opcoes,
    String? preferido,
  }) {
    if (opcoes.isEmpty) return null;
    final p = (preferido ?? '').trim();
    if (p.isEmpty || p == 'Nao definido') return opcoes.first;
    for (final n in opcoes) {
      if (n.toLowerCase() == p.toLowerCase()) return n;
    }
    return opcoes.first;
  }
}

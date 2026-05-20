import 'dart:convert';

class RecebimentoFiadoAlocacao {
  const RecebimentoFiadoAlocacao({
    required this.tituloId,
    required this.valor,
  });

  final int tituloId;
  final double valor;

  Map<String, dynamic> toJson() => {'tituloId': tituloId, 'valor': valor};

  static RecebimentoFiadoAlocacao fromJson(Map<String, dynamic> json) {
    return RecebimentoFiadoAlocacao(
      tituloId: ((json['tituloId'] as num?) ?? 0).toInt(),
      valor: ((json['valor'] as num?) ?? 0).toDouble(),
    );
  }
}

abstract final class RecebimentoFiadoCodec {
  static String encode(List<RecebimentoFiadoAlocacao> linhas) {
    return jsonEncode(linhas.map((e) => e.toJson()).toList());
  }

  static List<RecebimentoFiadoAlocacao> decode(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => RecebimentoFiadoAlocacao.fromJson(e.cast<String, dynamic>()))
          .where((l) => l.tituloId > 0 && l.valor > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

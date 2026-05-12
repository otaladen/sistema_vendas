import 'dart:convert';

/// Linha de item em falta na ida (complemento pendente).
class LinhaComplementoEntrega {
  const LinhaComplementoEntrega({
    required this.itemVendaId,
    required this.quantidade,
    required this.nomeProduto,
  });

  final int itemVendaId;
  final int quantidade;
  final String nomeProduto;

  Map<String, dynamic> toJson() => {
    'itemVendaId': itemVendaId,
    'quantidade': quantidade,
    'nomeProduto': nomeProduto,
  };

  static LinhaComplementoEntrega fromJson(Map<String, dynamic> m) {
    return LinhaComplementoEntrega(
      itemVendaId: (m['itemVendaId'] as num?)?.toInt() ?? 0,
      quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
      nomeProduto: (m['nomeProduto'] ?? '').toString(),
    );
  }
}

/// JSON em [Venda.complementoEntregaJson].
class ComplementoEntregaCodec {
  static String encode(List<LinhaComplementoEntrega> linhas) {
    return jsonEncode(linhas.map((e) => e.toJson()).toList());
  }

  static List<LinhaComplementoEntrega> decode(String raw) {
    if (raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => LinhaComplementoEntrega.fromJson(Map<String, dynamic>.from(m)))
        .where((e) => e.itemVendaId > 0 && e.quantidade > 0)
        .toList();
  }
}

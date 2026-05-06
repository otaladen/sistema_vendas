import 'dart:convert';

/// Uma linha do pagamento (PDV envia pronto; caixa apenas confere e finaliza).
class PagamentoOrcamentoLinha {
  const PagamentoOrcamentoLinha({
    required this.meio,
    required this.valor,
    this.parcelas = 1,
  });

  final String meio;
  final double valor;
  /// Para [cartao_credito]; demais meios usam 1.
  final int parcelas;

  Map<String, dynamic> toJson() => {
        'meio': meio,
        'valor': valor,
        'parcelas': parcelas,
      };

  static PagamentoOrcamentoLinha fromJson(Map<String, dynamic> json) {
    return PagamentoOrcamentoLinha(
      meio: (json['meio'] ?? '').toString(),
      valor: ((json['valor'] as num?) ?? 0).toDouble(),
      parcelas: ((json['parcelas'] as num?) ?? 1).toInt().clamp(1, 99),
    );
  }
}

/// Utilitarios para o campo [Venda.pagamentosJson].
abstract final class PagamentoOrcamentoCodec {
  static String encode(List<PagamentoOrcamentoLinha> linhas) {
    return jsonEncode(linhas.map((e) => e.toJson()).toList());
  }

  static List<PagamentoOrcamentoLinha> decode(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => PagamentoOrcamentoLinha.fromJson(e.cast<String, dynamic>()))
          .where((l) => l.meio.isNotEmpty && l.valor > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static double soma(List<PagamentoOrcamentoLinha> linhas) =>
      linhas.fold<double>(0, (a, b) => a + b.valor);

  static double somaPorMeio(List<PagamentoOrcamentoLinha> linhas, String meio) =>
      linhas.where((l) => l.meio == meio).fold<double>(0, (a, b) => a + b.valor);
}

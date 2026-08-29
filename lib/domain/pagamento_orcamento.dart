import 'dart:convert';

/// Uma linha de pagamento do orcamento (pagamento misto usa varias).
class PagamentoOrcamentoLinha {
  const PagamentoOrcamentoLinha({
    required this.meio,
    required this.valor,
    this.parcelas = 1,
    this.valeId = 0,
    this.codigoVale = '',
  });

  final String meio;
  final double valor;

  /// Para [cartao_credito]; demais meios usam 1.
  final int parcelas;

  /// Qual vale paga esta linha, quando [meio] e [PagamentoMeio.vale].
  /// Sem isso nao daria para saber de qual vale dar baixa ao fechar a venda.
  final int valeId;
  final String codigoVale;

  Map<String, dynamic> toJson() => {
        'meio': meio,
        'valor': valor,
        'parcelas': parcelas,
        if (valeId > 0) 'valeId': valeId,
        if (codigoVale.isNotEmpty) 'codigoVale': codigoVale,
      };

  static PagamentoOrcamentoLinha fromJson(Map<String, dynamic> json) {
    return PagamentoOrcamentoLinha(
      meio: (json['meio'] ?? '').toString(),
      valor: ((json['valor'] as num?) ?? 0).toDouble(),
      parcelas: ((json['parcelas'] as num?) ?? 1).toInt().clamp(1, 99),
      valeId: ((json['valeId'] as num?) ?? 0).toInt(),
      codigoVale: (json['codigoVale'] ?? '').toString(),
    );
  }
}

/// Identificadores dos meios de pagamento gravados em [PagamentoOrcamentoLinha].
abstract final class PagamentoMeio {
  static const dinheiro = 'dinheiro';
  static const pix = 'pix';
  static const cartaoDebito = 'cartao_debito';
  static const cartaoCredito = 'cartao_credito';
  static const transferencia = 'transferencia';
  static const fiado = 'fiado';

  /// Vale de credito de devolucao: nao entra dinheiro no caixa, ja foi pago
  /// na compra original.
  static const vale = 'vale';

  static const misto = 'misto';
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

  /// Linhas de vale com id resolvido, para dar baixa depois de fechar a venda.
  static List<PagamentoOrcamentoLinha> linhasVale(
    List<PagamentoOrcamentoLinha> linhas,
  ) =>
      linhas
          .where((l) => l.meio == PagamentoMeio.vale && l.valeId > 0)
          .toList();
}

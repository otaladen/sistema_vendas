import 'dart:convert';

import '../model/venda.dart';
import 'limite_credito_helper.dart';

/// Parcela do plano de quitação do fiado (definido no PDV).
class PlanoFiadoParcela {
  const PlanoFiadoParcela({
    required this.numero,
    required this.valor,
    required this.vencimento,
  });

  final int numero;
  final double valor;
  final DateTime vencimento;

  Map<String, dynamic> toJson() => {
        'numero': numero,
        'valor': valor,
        'vencimento': vencimento.toUtc().toIso8601String(),
      };

  static PlanoFiadoParcela fromJson(Map<String, dynamic> json) {
    return PlanoFiadoParcela(
      numero: ((json['numero'] as num?) ?? 1).toInt(),
      valor: ((json['valor'] as num?) ?? 0).toDouble(),
      vencimento:
          DateTime.tryParse((json['vencimento'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}

/// JSON em [Venda.planoFiadoJson].
abstract final class PlanoFiadoCodec {
  static String encode(List<PlanoFiadoParcela> parcelas) {
    return jsonEncode(parcelas.map((e) => e.toJson()).toList());
  }

  static List<PlanoFiadoParcela> decode(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => PlanoFiadoParcela.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.valor > 0)
          .toList()
        ..sort((a, b) => a.numero.compareTo(b.numero));
    } catch (_) {
      return [];
    }
  }

  static double soma(List<PlanoFiadoParcela> parcelas) =>
      parcelas.fold<double>(0, (a, b) => a + b.valor);

  static bool validarContraValor(
    List<PlanoFiadoParcela> parcelas,
    double valorFiado,
  ) {
    if (valorFiado <= 0.001) return parcelas.isEmpty;
    if (parcelas.isEmpty) return false;
    if ((soma(parcelas) - valorFiado).abs() > 0.02) return false;
    for (final p in parcelas) {
      if (p.valor <= 0) return false;
    }
    return true;
  }

  /// Divide [valorTotal] em [quantidade] parcelas (ultima ajusta centavos).
  static List<PlanoFiadoParcela> gerarParcelasIguais({
    required double valorTotal,
    required int quantidade,
    DateTime? primeiroVencimento,
    int diasEntreParcelas = 30,
  }) {
    if (quantidade < 1 || valorTotal <= 0) return [];
    final base = primeiroVencimento ?? DateTime.now().add(const Duration(days: 30));
    final valorParcela = (valorTotal / quantidade * 100).round() / 100;
    var acumulado = 0.0;
    final out = <PlanoFiadoParcela>[];
    for (var i = 0; i < quantidade; i++) {
      final venc = DateTime(
        base.year,
        base.month,
        base.day,
      ).add(Duration(days: diasEntreParcelas * i));
      final valor = i == quantidade - 1
          ? (valorTotal - acumulado).clamp(0, double.infinity).toDouble()
          : valorParcela;
      acumulado += valor;
      out.add(PlanoFiadoParcela(numero: i + 1, valor: valor, vencimento: venc));
    }
    return out;
  }

  static String formatarResumoLinhas(List<PlanoFiadoParcela> parcelas) {
    if (parcelas.isEmpty) return '-';
    return parcelas
        .map((p) => linhaResumoParcela(p, parcelas.length))
        .join(' · ');
  }

  static String linhaResumoParcela(PlanoFiadoParcela p, int totalParcelas) {
    final d = p.vencimento.toLocal();
    final data =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final v = p.valor.toStringAsFixed(2).replaceAll('.', ',');
    // Hifen ASCII: travessao Unicode some em fontes do pacote pdf.
    return '${p.numero}/$totalParcelas: R\$ $v - venc. $data';
  }

  static List<PlanoFiadoParcela> parcelasDaVenda(Venda venda) =>
      decode(venda.planoFiadoJson);

  /// Parcelas para exibir no cupom/PDF (JSON do PDV ou fallback 1x).
  static List<PlanoFiadoParcela> parcelasParaCupom(Venda venda) {
    final valorFiado = LimiteCreditoHelper.valorFiadoNaVenda(venda);
    if (valorFiado <= 0.001) return [];
    final doJson = parcelasDaVenda(venda);
    if (validarContraValor(doJson, valorFiado)) return doJson;
    if (doJson.isNotEmpty) return doJson;
    return gerarParcelasIguais(
      valorTotal: valorFiado,
      quantidade: 1,
      primeiroVencimento: venda.data.toUtc().add(const Duration(days: 30)),
    );
  }

  /// Venda/orçamento com fiado a exibir no cupom.
  static bool vendaTemPlanoQuitacao(Venda venda) =>
      parcelasParaCupom(venda).isNotEmpty;

  /// Linhas para cupom / orçamento PDF (texto puro).
  static List<String> linhasTextoPdf(Venda venda) {
    final parcelas = parcelasParaCupom(venda);
    if (parcelas.isEmpty) return [];
    final total = parcelas.length;
    return parcelas.map((p) => linhaResumoParcela(p, total)).toList();
  }

  /// Linhas extras de altura estimada para layout térmico.
  static int contarLinhasPdf(Venda venda) {
    final linhas = linhasTextoPdf(venda);
    if (linhas.isEmpty) return 0;
    return 1 + linhas.length;
  }
}

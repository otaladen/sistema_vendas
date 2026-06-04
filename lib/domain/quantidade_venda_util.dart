import '../model/produto.dart';

/// Conversao entre quantidade digitada no PDV e [ItemVenda.quantidade] (int).
///
/// Produtos com [Produto.permiteQuantidadeFracionada] armazenam milésimos
/// (ex.: 4,5 -> 4500) para manter compatibilidade com estoque inteiro e NF-e.
class QuantidadeVendaUtil {
  QuantidadeVendaUtil._();

  static const int escalaFracionada = 1000;

  /// Interpreta texto do PDV (aceita vírgula ou ponto).
  static double? parseEntradaPdv(String texto, {required bool fracionada}) {
    var t = texto.trim();
    if (t.isEmpty) return null;
    t = t.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '.');
    }
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v <= 0) return null;
    if (!fracionada && v != v.roundToDouble()) return null;
    return v;
  }

  static String formatarExibicao(
    double quantidade, {
    required bool fracionada,
  }) {
    if (!fracionada) return quantidade.round().toString();
    final arred = (quantidade * escalaFracionada).round() / escalaFracionada;
    if (arred == arred.roundToDouble()) {
      return arred.toStringAsFixed(0);
    }
    var s = arred.toStringAsFixed(3);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s.replaceAll('.', ',');
  }

  static double valorExibicao(int armazenado, {required bool fracionada}) {
    if (!fracionada) return armazenado.toDouble();
    return armazenado / escalaFracionada;
  }

  static int paraArmazenamento(double quantidade, {required bool fracionada}) {
    if (!fracionada) return quantidade.round();
    return (quantidade * escalaFracionada).round();
  }

  /// Quantidade inteira para baixa de estoque / promocao.
  static int paraEstoqueInteiro(Produto produto, int quantidadeArmazenada) {
    final q = valorExibicao(
      quantidadeArmazenada,
      fracionada: produto.permiteQuantidadeFracionada,
    );
    if (q <= 0) return 0;
    return q.round();
  }

  /// True se o texto parece quantidade decimal (ex.: 1,5 ou 2.75).
  static bool textoPareceQuantidadeDecimal(String texto) {
    final t = texto.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (t.isEmpty) return false;
    if (t.contains(',')) return true;
    final ponto = t.indexOf('.');
    if (ponto <= 0) return false;
    final depois = t.substring(ponto + 1);
    return depois.isNotEmpty && RegExp(r'^\d+$').hasMatch(depois);
  }
}

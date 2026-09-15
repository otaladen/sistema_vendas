import '../model/item_venda.dart';
import '../model/venda.dart';

/// Totais de orcamento para impressao (ESC/POS/PDF), com parse defensivo e
/// desconto derivado do [total] persistido no servidor — nao de [Venda.itens]
/// solto no terminal (pode estar sem produto e inflar subtotal).
abstract final class OrcamentoTotaisImpressao {
  OrcamentoTotaisImpressao._();

  static const _epsilon = 0.01;

  /// Converte JSON/LanApi (`num`, centavos `int`, string) em reais.
  static double parseMoeda(dynamic v) {
    if (v == null) return 0;
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : 0;
    }
    if (v is String) {
      var t = v.trim();
      if (t.isEmpty) return 0;
      t = t.replaceAll(RegExp(r'[R$\s]'), '');
      if (t.contains(',') && t.contains('.')) {
        t = t.replaceAll('.', '').replaceAll(',', '.');
      } else if (t.contains(',')) {
        t = t.replaceAll(',', '.');
      }
      final d = double.tryParse(t);
      return d != null && d.isFinite ? d : 0;
    }
    return 0;
  }

  static double totalInformado(Venda venda) => parseMoeda(venda.total);

  static double freteInformado(Venda venda) {
    final f = parseMoeda(venda.valorFrete);
    return f > _epsilon ? f : 0;
  }

  static ({double subtotalItens, double bruto, double desconto, double total})
      calcular({
    required Venda venda,
    required List<ItemVenda> itens,
  }) {
    final subtotalItens = itens.fold<double>(
      0,
      (s, i) => s + parseMoeda(i.subtotal),
    );
    final frete = freteInformado(venda);
    final bruto = subtotalItens + frete;
    final totalSrv = totalInformado(venda);

    if (itens.isEmpty) {
      return (
        subtotalItens: subtotalItens,
        bruto: bruto,
        desconto: 0,
        total: totalSrv,
      );
    }

    final desconto = totalSrv > _epsilon
        ? (bruto - totalSrv).clamp(0.0, double.infinity)
        : 0.0;
    final total = totalSrv > _epsilon
        ? totalSrv
        : (bruto - desconto).clamp(0.0, double.infinity);

    return (
      subtotalItens: subtotalItens,
      bruto: bruto,
      desconto: desconto,
      total: total,
    );
  }

  static bool imprimirLinhaDesconto(double desconto) => desconto > _epsilon;
}

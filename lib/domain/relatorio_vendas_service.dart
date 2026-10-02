import '../model/item_venda.dart';
import '../model/produto.dart';
import 'produto_embalagem.dart';

/// Metricas de uma linha de venda para relatorios (quantidade real, CMV, lucro).
class RelatorioMetricasItemVenda {
  const RelatorioMetricasItemVenda({
    required this.quantidadeReal,
    required this.faturamentoTotal,
    required this.custoTotal,
    required this.lucro,
    required this.margemPercentual,
    this.margemIrreal = false,
  });

  final double quantidadeReal;
  final double faturamentoTotal;
  final double custoTotal;
  final double lucro;
  final double margemPercentual;

  /// Margem acima do limite operacional — revisar cadastro/escala da linha.
  final bool margemIrreal;

  static const double margemPercentualMaximaRealista = 1000;
}

/// Formulas e escala de quantidade para relatorios de vendas.
abstract final class RelatorioVendasService {
  RelatorioVendasService._();

  static double quantidadeVendaEfetivaDeArmazenada({
    required Produto? produto,
    required int quantidadeArmazenada,
    bool? emMilesimos,
  }) {
    if (quantidadeArmazenada <= 0) return 0;
    return ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: quantidadeArmazenada,
      emMilesimos: emMilesimos,
    );
  }

  /// Quantidade liquida na unidade de venda (desconta devolucao na mesma escala).
  static double quantidadeRealLiquidaItem({
    required ItemVenda item,
    Produto? produto,
  }) {
    produto ??= item.produtoOuNull;
    final emMil = item.quantidadeEmMilesimosPersistida;
    final total = quantidadeVendaEfetivaDeArmazenada(
      produto: produto,
      quantidadeArmazenada: item.quantidade,
      emMilesimos: emMil,
    );
    if (item.quantidadeDevolvida <= 0) return total;
    final devolvida = quantidadeVendaEfetivaDeArmazenada(
      produto: produto,
      quantidadeArmazenada: item.quantidadeDevolvida,
      emMilesimos: emMil,
    );
    final liq = total - devolvida;
    return liq <= 0 ? 0 : liq;
  }

  static RelatorioMetricasItemVenda metricasItemVenda({
    required ItemVenda item,
    Produto? produto,
  }) {
    final q = quantidadeRealLiquidaItem(item: item, produto: produto);
    if (q <= 0) {
      return const RelatorioMetricasItemVenda(
        quantidadeReal: 0,
        faturamentoTotal: 0,
        custoTotal: 0,
        lucro: 0,
        margemPercentual: 0,
      );
    }
    final faturamento = q * item.precoUnitario;
    final custo = q * item.precoCustoUnitario;
    final lucro = faturamento - custo;
    final margem = faturamento > 0 ? (lucro / faturamento) * 100 : 0.0;
    final irreal =
        margem.abs() > RelatorioMetricasItemVenda.margemPercentualMaximaRealista;
    return RelatorioMetricasItemVenda(
      quantidadeReal: q,
      faturamentoTotal: faturamento,
      custoTotal: custo,
      lucro: lucro,
      margemPercentual: irreal ? 0 : margem,
      margemIrreal: irreal,
    );
  }

  static double margemPercentual({
    required double faturamentoTotal,
    required double lucro,
  }) {
    if (faturamentoTotal.abs() < 0.01) return 0;
    final m = (lucro / faturamentoTotal) * 100;
    if (m.abs() > RelatorioMetricasItemVenda.margemPercentualMaximaRealista) {
      return 0;
    }
    return m;
  }

  static double deltaQuantidadeReal({
    required int deltaQuantidadeArmazenada,
    required Produto? produto,
    bool? emMilesimos,
  }) {
    if (deltaQuantidadeArmazenada == 0) return 0;
    final sinal = deltaQuantidadeArmazenada < 0 ? -1.0 : 1.0;
    final abs = deltaQuantidadeArmazenada.abs();
    return sinal *
        quantidadeVendaEfetivaDeArmazenada(
          produto: produto,
          quantidadeArmazenada: abs,
          emMilesimos: emMilesimos,
        );
  }
}

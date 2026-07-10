/// Calculo de custo medio ponderado em entradas de estoque (NF-e).
abstract final class CustoMedioEntradaUtil {
  /// Apos uma entrada: media ponderada do saldo anterior + quantidade da nota.
  static double? custoMedioAposEntrada({
    required int estoqueAntes,
    required double custoMedioAntes,
    required int quantidadeEntrada,
    required double custoUnitarioEntrada,
  }) {
    if (quantidadeEntrada <= 0 || custoUnitarioEntrada <= 0) {
      return custoMedioAntes > 0 ? custoMedioAntes : null;
    }
    final estoqueDepois = estoqueAntes + quantidadeEntrada;
    if (estoqueDepois <= 0) return custoUnitarioEntrada;
    final custoAntes = custoMedioAntes > 0 ? custoMedioAntes : 0.0;
    if (estoqueAntes <= 0 || custoAntes <= 0) {
      return custoUnitarioEntrada;
    }
    return (estoqueAntes * custoAntes + quantidadeEntrada * custoUnitarioEntrada) /
        estoqueDepois;
  }

  /// Custo medio imediatamente antes de uma entrada registrada no historico.
  static double? custoMedioAntesEntrada({
    required int estoqueAposEstorno,
    required int quantidadeEntradaEstornada,
    required double custoMedioAtual,
    required double custoUnitarioEntrada,
  }) {
    if (quantidadeEntradaEstornada <= 0) {
      return custoMedioAtual > 0 ? custoMedioAtual : null;
    }
    final estoqueAntesEntrada = estoqueAposEstorno + quantidadeEntradaEstornada;
    if (estoqueAposEstorno <= 0) return null;
    if (estoqueAntesEntrada <= quantidadeEntradaEstornada) return null;
    final saldoAnterior = estoqueAntesEntrada - quantidadeEntradaEstornada;
    if (saldoAnterior <= 0) return null;
    final numerador = custoMedioAtual * estoqueAntesEntrada -
        custoUnitarioEntrada * quantidadeEntradaEstornada;
    if (numerador <= 0) return null;
    return numerador / saldoAnterior;
  }

  /// Custo de referencia do saldo antes da entrada (custo medio ou preco de custo).
  static double custoReferenciaSaldo({
    required double custoMedio,
    required double precoCusto,
  }) {
    if (custoMedio > 0) return custoMedio;
    if (precoCusto > 0) return precoCusto;
    return 0;
  }
}

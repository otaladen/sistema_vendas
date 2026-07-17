import 'tipo_movimento_estoque.dart';

/// Rotulos e utilidades do kardex de estoque.
abstract final class MovimentoEstoqueHelper {
  static String rotuloTipo(String tipoMovimento) {
    for (final t in TipoMovimentoEstoque.values) {
      if (t.name == tipoMovimento) return rotuloTipoEnum(t);
    }
    return tipoMovimento.isEmpty ? 'Movimento' : tipoMovimento;
  }

  static String rotuloTipoEnum(TipoMovimentoEstoque tipo) {
    switch (tipo) {
      case TipoMovimentoEstoque.orcamentoReserva:
        return 'Reserva orcamento';
      case TipoMovimentoEstoque.orcamentoLiberaReserva:
        return 'Libera reserva orcamento';
      case TipoMovimentoEstoque.finalizacaoAjustaReserva:
        return 'Ajuste reserva caixa';
      case TipoMovimentoEstoque.cupomNaoFiscalVenda:
        return 'Cupom nao fiscal (retirada)';
      case TipoMovimentoEstoque.entradaNfeCompra:
        return 'Entrada NF-e compra';
      case TipoMovimentoEstoque.estornoEntradaNfeCompra:
        return 'Estorno entrada NF-e';
      case TipoMovimentoEstoque.carretoSaida:
        return 'Saida carreto';
      case TipoMovimentoEstoque.carretoEstornoSaida:
        return 'Estorno saida carreto';
      case TipoMovimentoEstoque.retiradaParcialCliente:
        return 'Retirada parcial cliente';
      case TipoMovimentoEstoque.retiradaTotalImediata:
        return 'Retirada total imediata';
      case TipoMovimentoEstoque.complementoEntregaFalta:
        return 'Complemento entrega (falta)';
      case TipoMovimentoEstoque.complementoEntregaBaixa:
        return 'Baixa complemento entrega';
      case TipoMovimentoEstoque.cancelamentoVendaEstorno:
        return 'Estorno cancelamento venda';
      case TipoMovimentoEstoque.devolucaoCliente:
        return 'Devolucao / troca';
      case TipoMovimentoEstoque.devolucaoFornecedor:
        return 'Devolucao ao fornecedor';
      case TipoMovimentoEstoque.ajusteManual:
        return 'Ajuste manual';
      case TipoMovimentoEstoque.vendaDiretaLegada:
        return 'Venda direta (legado)';
      case TipoMovimentoEstoque.nfceEmissao:
        return 'NFC-e (sem estoque)';
      case TipoMovimentoEstoque.nfeVendaEmissao:
        return 'NF-e venda (sem estoque)';
    }
  }

  static String formatarDelta(int delta) {
    if (delta > 0) return '+$delta';
    return '$delta';
  }
}

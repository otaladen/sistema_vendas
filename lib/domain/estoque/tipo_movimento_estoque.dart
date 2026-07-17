/// Origem de uma alteracao em [Produto.estoqueReal] / [Produto.estoqueReservado].
///
/// Politica do ERP: apenas movimentos que representam saida/entrada fisica real
/// (cupom nao fiscal de venda, entrada de compra, carreto, retirada, estorno)
/// alteram [estoqueReal]. NFC-e e NF-e de **venda** nao movimentam estoque.
enum TipoMovimentoEstoque {
  /// Reserva ao gravar/editar orcamento (retirada futura / carreto).
  orcamentoReserva,

  /// Libera reserva ao cancelar or editar orcamento.
  orcamentoLiberaReserva,

  /// Ajuste de reserva na finalizacao no caixa (sem baixa fisica de retirada imediata).
  finalizacaoAjustaReserva,

  /// Baixa fisica de itens retirados na loja — disparada pelo cupom nao fiscal.
  cupomNaoFiscalVenda,

  /// Entrada de mercadoria via conferencia de XML de compra.
  entradaNfeCompra,

  /// Estorno de entrada de NF-e de compra.
  estornoEntradaNfeCompra,

  /// Baixa fisica ao marcar carga "saiu" (carreto).
  carretoSaida,

  /// Estorno ao desmarcar saida do carreto.
  carretoEstornoSaida,

  /// Retirada parcial de retirada futura.
  retiradaParcialCliente,

  /// Retirada total imediata apos pendencia.
  retiradaTotalImediata,

  /// Credito de estoque por complemento de entrega (falta na ida).
  complementoEntregaFalta,

  /// Baixa de complemento de entrega na conclusao.
  complementoEntregaBaixa,

  /// Estorno ao cancelar venda finalizada.
  cancelamentoVendaEstorno,

  /// Devolucao/troca pos-entrega.
  devolucaoCliente,

  /// Baixa fisica ao devolver mercadoria ao fornecedor/fabrica (NF-e).
  devolucaoFornecedor,

  /// Ajuste manual na tela de estoque ou cadastro.
  ajusteManual,

  /// Venda direta legada ([VendaRepository.registrarVenda]).
  vendaDiretaLegada,

  /// Emissao NFC-e — apenas faturamento (bloqueado para estoque).
  nfceEmissao,

  /// NF-e de venda — apenas faturamento (bloqueado para estoque).
  nfeVendaEmissao,
}

/// Regras de quais tipos podem alterar estoque fisico ([estoqueReal]).
abstract final class PoliticaMovimentoEstoque {
  static bool alteraEstoqueFisico(TipoMovimentoEstoque tipo) {
    switch (tipo) {
      case TipoMovimentoEstoque.cupomNaoFiscalVenda:
      case TipoMovimentoEstoque.entradaNfeCompra:
      case TipoMovimentoEstoque.estornoEntradaNfeCompra:
      case TipoMovimentoEstoque.carretoSaida:
      case TipoMovimentoEstoque.carretoEstornoSaida:
      case TipoMovimentoEstoque.retiradaParcialCliente:
      case TipoMovimentoEstoque.retiradaTotalImediata:
      case TipoMovimentoEstoque.complementoEntregaFalta:
      case TipoMovimentoEstoque.complementoEntregaBaixa:
      case TipoMovimentoEstoque.cancelamentoVendaEstorno:
      case TipoMovimentoEstoque.devolucaoCliente:
      case TipoMovimentoEstoque.devolucaoFornecedor:
      case TipoMovimentoEstoque.ajusteManual:
      case TipoMovimentoEstoque.vendaDiretaLegada:
        return true;
      case TipoMovimentoEstoque.orcamentoReserva:
      case TipoMovimentoEstoque.orcamentoLiberaReserva:
      case TipoMovimentoEstoque.finalizacaoAjustaReserva:
      case TipoMovimentoEstoque.nfceEmissao:
      case TipoMovimentoEstoque.nfeVendaEmissao:
        return false;
    }
  }

  static bool alteraSomenteReserva(TipoMovimentoEstoque tipo) {
    switch (tipo) {
      case TipoMovimentoEstoque.orcamentoReserva:
      case TipoMovimentoEstoque.orcamentoLiberaReserva:
      case TipoMovimentoEstoque.finalizacaoAjustaReserva:
        return true;
      default:
        return false;
    }
  }

  static void validarPermiteAlteracaoFisica(TipoMovimentoEstoque tipo) {
    if (!alteraEstoqueFisico(tipo)) {
      throw StateError(
        'Movimento de estoque "$tipo" nao pode alterar estoque fisico. '
        'NFC-e/NF-e de venda sao apenas faturamento; use cupom nao fiscal.',
      );
    }
  }

  static void validarNaoAlteraEstoque(TipoMovimentoEstoque tipo) {
    if (alteraEstoqueFisico(tipo)) {
      throw StateError(
        'Documento fiscal nao deve chamar baixa de estoque ($tipo).',
      );
    }
  }
}

import '../domain/entrega_venda_helper.dart';

/// Regras para pular modais no PDV (modo balcao rapido).
abstract final class PdvBalcaoRapidoHelper {
  /// Adiciona item direto sem dialog (qtd 1, preco/entrega do cabecalho).
  static bool podeAdicionarDireto({
    required bool carrinhoTemCarreto,
    required String tipoEntregaSelecionada,
    required bool pagamentoMisto,
    required bool edicaoOrcamento,
  }) {
    if (edicaoOrcamento) return false;
    if (pagamentoMisto) return false;
    if (carrinhoTemCarreto) return false;
    if (tipoEntregaSelecionada != EntregaVendaHelper.tipoRetirada) {
      return false;
    }
    return true;
  }

  /// Salva orcamento sem abrir dialog de checkout (dados ja no cabecalho).
  static bool podeCheckoutDireto({
    required bool carrinhoTemCarreto,
    required bool pagamentoMisto,
    required bool precisaPlanoFiado,
    required bool temDescontoInformado,
    required bool edicaoOrcamento,
  }) {
    if (edicaoOrcamento) return false;
    if (carrinhoTemCarreto) return false;
    if (pagamentoMisto) return false;
    if (precisaPlanoFiado) return false;
    if (temDescontoInformado) return false;
    return true;
  }
}

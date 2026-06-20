import '../model/venda.dart';
import 'entrega_venda_helper.dart';

/// Etapa fiscal pos-pagamento no caixa (estoque x documento fiscal).
abstract final class VendaDocumentoPosCaixa {
  VendaDocumentoPosCaixa._();

  /// Estoque de retirada imediata baixado na finalizacao (modelo ERP de balcao).
  static bool estoqueOperacionalOk(Venda venda) {
    if (!EntregaVendaHelper.vendaTemItensRetiradaImediataPendenteCupom(venda)) {
      return true;
    }
    return venda.estoqueBaixadoCupom;
  }

  /// Pode encerrar a etapa fiscal: estoque OK; NFC-e pode continuar pendente.
  static bool podeEncerrarEtapaFiscal(Venda venda) =>
      estoqueOperacionalOk(venda);

  /// Alias usado no caixa — significa estoque operacional, nao nota fiscal.
  static bool registrado(Venda venda) => estoqueOperacionalOk(venda);
}

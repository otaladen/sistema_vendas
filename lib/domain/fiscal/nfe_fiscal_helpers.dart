import 'fiscal_regime_padrao.dart';
import '../../model/cliente.dart';
import '../../model/produto.dart';
import '../../services/focus_nfe_service.dart';
import 'produto_fiscal_catalog.dart';

/// Utilitarios compartilhados entre emissao NF-e e conferencia na UI.
abstract final class NfeFiscalHelpers {
  NfeFiscalHelpers._();

  static String indicadorIeCliente(Cliente cliente) {
    final ind = cliente.indicadorIe.trim().toLowerCase();
    if (ind == 'contribuinte') return '1';
    if (ind == 'isento') return '2';
    if (cliente.inscricaoEstadual.replaceAll(RegExp(r'\D'), '').isNotEmpty) {
      return '1';
    }
    return '9';
  }

  static bool consumidorFinalDestinatario(FocusNfeDestinatarioNfe destinatario) {
    final doc = destinatario.documento.replaceAll(RegExp(r'\D'), '');
    if (doc.length == 11) return true;
    return destinatario.indicadorInscricaoEstadual == '9';
  }

  static bool consumidorFinalCliente(Cliente cliente) {
    final doc = cliente.documento.replaceAll(RegExp(r'\D'), '');
    if (doc.length == 11) return true;
    return indicadorIeCliente(cliente) == '9';
  }

  static String codigoGtinProduto(Produto produto) {
    final digits = produto.codigoBarras.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8 ||
        digits.length == 12 ||
        digits.length == 13 ||
        digits.length == 14) {
      return digits;
    }
    return 'SEM GTIN';
  }

  static String icmsCstProduto(Produto produto) {
    return ProdutoFiscalCatalog.resolverIcmsSituacaoTributaria(
      produto,
      icmsPadraoLoja: FiscalRegimePadrao.icmsSituacaoTributariaPadrao(),
      ehSimplesNacional: FiscalRegimePadrao.ehSimplesNacional(),
    );
  }

  static String pisCofinsCstProduto(Produto produto) {
    return ProdutoFiscalCatalog.resolverPisCofinsSituacaoTributaria(
      produto,
      pisCofinsPadraoLoja: FiscalRegimePadrao.pisCofinsSituacaoTributariaPadrao(),
    );
  }
}

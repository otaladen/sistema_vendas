import '../../config/fiscal_config.dart';
import '../../model/produto.dart';
import 'grupo_tributario_produto.dart';

/// CFOP de NF-e de devolucao de compra (loja → fornecedor/fabrica).
///
/// Padrao de material de construcao / varejo: CFOP 5202 (UF) ou 6202 (interestadual),
/// com variantes ST 5411/6411.
abstract final class NfeCfopDevolucaoFornecedorResolver {
  NfeCfopDevolucaoFornecedorResolver._();

  static String resolver({
    required Produto produto,
    required String ufDestinatario,
    String ufEmitente = FiscalConfig.ufEmitente,
  }) {
    final grupo = grupoTributarioProdutoDeString(produto.grupoTributario);
    final emitente = ufEmitente.trim().toUpperCase();
    final dest = ufDestinatario.trim().toUpperCase();
    final interestadual = dest.isNotEmpty && dest != emitente;

    if (interestadual) {
      return grupo == GrupoTributarioProduto.substituicaoTributaria
          ? FiscalConfig.cfopDevolucaoCompraInterestadualSt
          : FiscalConfig.cfopDevolucaoCompraInterestadual;
    }
    return grupo == GrupoTributarioProduto.substituicaoTributaria
        ? FiscalConfig.cfopDevolucaoCompraEstadualSt
        : FiscalConfig.cfopDevolucaoCompraEstadual;
  }
}

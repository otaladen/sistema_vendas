import '../../config/fiscal_config.dart';
import '../../model/produto.dart';
import 'grupo_tributario_produto.dart';

/// CFOP de NF-e de devolucao (finalidade 4) quando o cliente devolve mercadoria.
abstract final class NfeCfopDevolucaoResolver {
  NfeCfopDevolucaoResolver._();

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
      return _cfopInterestadual(grupo);
    }
    return _cfopEstadual(grupo);
  }

  static String _cfopEstadual(GrupoTributarioProduto grupo) {
    switch (grupo) {
      case GrupoTributarioProduto.substituicaoTributaria:
        return FiscalConfig.cfopDevolucaoVendaEstadualSt;
      case GrupoTributarioProduto.isento:
      case GrupoTributarioProduto.tributado:
        return FiscalConfig.cfopDevolucaoVendaEstadual;
    }
  }

  static String _cfopInterestadual(GrupoTributarioProduto grupo) {
    switch (grupo) {
      case GrupoTributarioProduto.substituicaoTributaria:
        return '2411';
      case GrupoTributarioProduto.isento:
      case GrupoTributarioProduto.tributado:
        return FiscalConfig.cfopDevolucaoVendaInterestadual;
    }
  }
}

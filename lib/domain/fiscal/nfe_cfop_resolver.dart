import '../../config/fiscal_config.dart';
import '../../model/produto.dart';
import 'grupo_tributario_produto.dart';

/// Matriz de CFOP para NF-e modelo 55 (revenda / construtora / interestadual).
abstract final class NfeCfopResolver {
  NfeCfopResolver._();

  /// CFOP manual no produto tem prioridade sobre a matriz.
  static String resolver({
    required Produto produto,
    required String ufDestinatario,
    required bool consumidorFinal,
    String ufEmitente = FiscalConfig.ufEmitente,
  }) {
    final cfopProduto = produto.cfopVenda.trim();
    if (cfopProduto.length == 4 && RegExp(r'^\d{4}$').hasMatch(cfopProduto)) {
      return cfopProduto;
    }

    final grupo = grupoTributarioProdutoDeString(produto.grupoTributario);
    final emitente = ufEmitente.trim().toUpperCase();
    final dest = ufDestinatario.trim().toUpperCase();
    final interestadual =
        dest.isNotEmpty && dest != emitente;

    if (interestadual) {
      return _cfopInterestadual(grupo);
    }

    if (!consumidorFinal) {
      return _cfopEstadualContribuinte(grupo);
    }

    return grupo.cfopVendaConsumidorFinalBahia;
  }

  static String _cfopInterestadual(GrupoTributarioProduto grupo) {
    switch (grupo) {
      case GrupoTributarioProduto.substituicaoTributaria:
        return FiscalConfig.cfopInterestadualSt;
      case GrupoTributarioProduto.isento:
      case GrupoTributarioProduto.tributado:
        return FiscalConfig.cfopInterestadualTributadoRevenda;
    }
  }

  static String _cfopEstadualContribuinte(GrupoTributarioProduto grupo) {
    switch (grupo) {
      case GrupoTributarioProduto.substituicaoTributaria:
        return FiscalConfig.cfopEstadualContribuinteSt;
      case GrupoTributarioProduto.isento:
      case GrupoTributarioProduto.tributado:
        return FiscalConfig.cfopEstadualContribuinteTributado;
    }
  }
}

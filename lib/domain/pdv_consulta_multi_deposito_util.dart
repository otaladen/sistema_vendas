import '../model/produto.dart';

/// Rotulos configuraveis para exibicao de estoque multi-deposito.
class PdvConsultaDepositoRotulos {
  const PdvConsultaDepositoRotulos({
    this.loja = 'Loja',
    this.cd = 'CD',
  });

  final String loja;
  final String cd;
}

abstract final class PdvConsultaMultiDepositoUtil {
  PdvConsultaMultiDepositoUtil._();

  static bool exibirCd(Produto produto) => produto.estoqueCd > 0;

  static String montarRotuloInsights(
    Produto produto, {
    PdvConsultaDepositoRotulos rotulos = const PdvConsultaDepositoRotulos(),
  }) {
    final partes = <String>[];
    final local = produto.localizacao.trim();
    if (local.isNotEmpty) partes.add('Local $local');
    partes.add('${rotulos.loja}: ${produto.estoqueLivreParaVenda}');
    if (exibirCd(produto)) {
      partes.add('${rotulos.cd}: ${produto.estoqueCd}');
    }
    return partes.join(' · ');
  }
}

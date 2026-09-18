import '../model/produto.dart';

/// Snapshot de um produto da NF-e para revisao de precos apos a importacao.
///
/// Valores sao copiados no momento da conferencia (antes da gravacao de custo),
/// para a tela de revisao nao depender do estado mutavel do cadastro.
class NfeRevisaoPrecoItem {
  const NfeRevisaoPrecoItem({
    required this.produtoId,
    required this.codigoInterno,
    required this.nome,
    required this.custoAntigo,
    required this.custoNovo,
    required this.margemLucroCadastrada,
    required this.precoVendaAtual,
    required this.precoVendaSugerido,
    this.produtoNovo = false,
  });

  final int produtoId;
  final String codigoInterno;
  final String nome;
  final double custoAntigo;
  final double custoNovo;

  /// Markup efetivo do cadastro: (preco venda - custo antigo) / custo antigo.
  final double margemLucroCadastrada;
  final double precoVendaAtual;
  final double precoVendaSugerido;
  final bool produtoNovo;

  bool get custoAumentou => custoNovo > custoAntigo + 0.005;
}

/// Regras de margem e preco sugerido na revisao pos-XML.
abstract final class NfeRevisaoPrecoCalculo {
  NfeRevisaoPrecoCalculo._();

  /// Markup % sobre o custo (o que o operador chama de "margem em cima do custo").
  static double markupPercentual(double precoVenda, double custo) {
    if (custo <= 0 || precoVenda <= 0) return 0;
    return ((precoVenda - custo) / custo) * 100;
  }

  /// Novo custo + margem cadastrada (markup). Sem margem no cadastro, usa o
  /// minimo da loja.
  static double precoVendaSugerido({
    required double custoNovo,
    required double margemCadastrada,
    required double margemMinimaPadrao,
  }) {
    if (custoNovo <= 0) return 0;
    final margem = margemCadastrada > 0.05
        ? margemCadastrada
        : margemMinimaPadrao.clamp(0, 500);
    final bruto = custoNovo * (1 + margem / 100);
    return (bruto * 100).roundToDouble() / 100;
  }

  static NfeRevisaoPrecoItem deProduto({
    required Produto produto,
    required double custoNovo,
    required double margemMinimaPadrao,
    bool produtoNovo = false,
  }) {
    final custoAntigo = produto.precoCusto < 0 ? 0.0 : produto.precoCusto;
    final precoAtual = produto.precoVenda > 0
        ? produto.precoVenda
        : (produto.preco1 > 0 ? produto.preco1 : 0.0);
    final margem = markupPercentual(precoAtual, custoAntigo);
    final custoXml = custoNovo > 0 ? custoNovo : custoAntigo;
    final sugerido = precoVendaSugerido(
      custoNovo: custoXml,
      margemCadastrada: margem,
      margemMinimaPadrao: margemMinimaPadrao,
    );
    return NfeRevisaoPrecoItem(
      produtoId: produto.id,
      codigoInterno: produto.codigoInterno,
      nome: produto.nome,
      custoAntigo: custoAntigo,
      custoNovo: custoXml,
      margemLucroCadastrada: margem,
      precoVendaAtual: precoAtual,
      precoVendaSugerido: sugerido > 0 ? sugerido : precoAtual,
      produtoNovo: produtoNovo,
    );
  }

  /// Uma linha por produto; se a nota repetir o item, fica o maior custo XML.
  static void upsert(
    Map<int, NfeRevisaoPrecoItem> destino,
    NfeRevisaoPrecoItem item,
  ) {
    if (item.produtoId <= 0) return;
    final prev = destino[item.produtoId];
    if (prev == null || item.custoNovo > prev.custoNovo) {
      destino[item.produtoId] = item;
    }
  }
}

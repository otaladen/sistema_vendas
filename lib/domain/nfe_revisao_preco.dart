import '../model/produto.dart';
import 'produto_precificacao.dart';

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
    required this.preco2Atual,
    required this.preco2Sugerido,
    required this.margemPreco2Cadastrada,
    required this.preco3Atual,
    required this.preco3Sugerido,
    required this.margemPreco3Cadastrada,
    this.produtoNovo = false,
  });

  final int produtoId;
  final String codigoInterno;
  final String nome;
  final double custoAntigo;
  final double custoNovo;

  /// Markup efetivo do cadastro (preco 1): (preco - custo antigo) / custo antigo.
  final double margemLucroCadastrada;
  final double precoVendaAtual;
  final double precoVendaSugerido;

  final double preco2Atual;
  final double preco2Sugerido;
  final double margemPreco2Cadastrada;

  final double preco3Atual;
  final double preco3Sugerido;
  final double margemPreco3Cadastrada;

  final bool produtoNovo;

  bool get custoAumentou => custoNovo > custoAntigo + 0.005;

  /// Variacao percentual do custo (antigo → novo). `null` se custo antigo era zero.
  double? get variacaoCustoPercentual {
    if (custoAntigo <= 1e-9) return null;
    return ((custoNovo - custoAntigo) / custoAntigo) * 100;
  }

  /// Repasse exato em R$: soma o delta de custo ao preco atual da tabela.
  double precoRepassandoAumentoCusto(double precoAtual) {
    if (precoAtual <= 0) return precoAtual;
    final delta = custoNovo - custoAntigo;
    return NfeRevisaoPrecoCalculo.arredondarCentavos(precoAtual + delta);
  }
}

/// Regras de margem e preco sugerido na revisao pos-XML.
abstract final class NfeRevisaoPrecoCalculo {
  NfeRevisaoPrecoCalculo._();

  static double arredondarCentavos(double v) =>
      (v * 100).roundToDouble() / 100;

  static double precoEfetivoTabela(Produto produto, int indiceTabela) {
    switch (indiceTabela) {
      case 2:
        return produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;
      case 3:
        return produto.preco3 > 0 ? produto.preco3 : produto.precoVenda;
      default:
        return produto.precoVenda > 0
            ? produto.precoVenda
            : (produto.preco1 > 0 ? produto.preco1 : 0.0);
    }
  }

  /// Margem sobre o preco de venda com o custo informado (alinhado ao minimo da loja).
  static double margemSobreVenda(double precoVenda, double custo) =>
      ProdutoPrecificacao.margemSobrePrecoVenda(
        custo: custo,
        precoVenda: precoVenda,
      );

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
    final precoAtual = precoEfetivoTabela(produto, 1);
    final preco2Atual = precoEfetivoTabela(produto, 2);
    final preco3Atual = precoEfetivoTabela(produto, 3);
    final margem = markupPercentual(precoAtual, custoAntigo);
    final margem2 = markupPercentual(preco2Atual, custoAntigo);
    final margem3 = markupPercentual(preco3Atual, custoAntigo);
    final custoXml = custoNovo > 0 ? custoNovo : custoAntigo;
    final sugerido = precoVendaSugerido(
      custoNovo: custoXml,
      margemCadastrada: margem,
      margemMinimaPadrao: margemMinimaPadrao,
    );
    final sugerido2 = precoVendaSugerido(
      custoNovo: custoXml,
      margemCadastrada: margem2,
      margemMinimaPadrao: margemMinimaPadrao,
    );
    final sugerido3 = precoVendaSugerido(
      custoNovo: custoXml,
      margemCadastrada: margem3,
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
      preco2Atual: preco2Atual,
      preco2Sugerido: sugerido2 > 0 ? sugerido2 : preco2Atual,
      margemPreco2Cadastrada: margem2,
      preco3Atual: preco3Atual,
      preco3Sugerido: sugerido3 > 0 ? sugerido3 : preco3Atual,
      margemPreco3Cadastrada: margem3,
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

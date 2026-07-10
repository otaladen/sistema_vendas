import '../../domain/produto_embalagem.dart';
import '../../domain/produto_precificacao.dart';
import '../../model/produto.dart';

/// Metricas derivadas para a listagem operacional de estoque.
abstract final class EstoqueListaMetricas {
  static double custoExibicao(Produto produto) =>
      produto.custoMedio > 0 ? produto.custoMedio : produto.precoCusto;

  static double precoVendaExibicao(Produto produto) =>
      produto.preco2 > 0 ? produto.preco2 : produto.precoVenda;

  static double margemPercentual(Produto produto) {
    return ProdutoPrecificacao.margemSobrePrecoVenda(
      custo: custoExibicao(produto),
      precoVenda: precoVendaExibicao(produto),
    );
  }

  /// Dias de estoque livre com base na media diaria. `null` = sem giro confiavel.
  static double? coberturaDias(Produto produto) {
    final media = produto.vendaMediaDiaria;
    if (media <= 0.001) return null;
    final disp = ProdutoEmbalagem.valorEstoqueExibicao(
      produto,
      produto.estoqueLivreParaVenda,
    );
    if (disp <= 0) return 0;
    return disp / media;
  }

  static String formatarMargem(Produto produto) {
    if (precoVendaExibicao(produto) <= 0) return '—';
    return '${margemPercentual(produto).toStringAsFixed(1)}%';
  }

  static String formatarCobertura(Produto produto) {
    final dias = coberturaDias(produto);
    if (dias == null) {
      return produto.estoqueLivreParaVenda > 0 ? '—' : '0d';
    }
    if (dias >= 999) return '999+';
    if (dias < 1) return '<1d';
    return '${dias.round()}d';
  }
}

/// Colunas ordenaveis da tabela de estoque.
enum EstoqueColunaOrdenacao {
  nenhuma,
  disponivel,
  margem,
  cobertura,
  media,
  venda,
}

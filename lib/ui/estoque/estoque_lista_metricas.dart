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

  /// Valor monetario do estoque fisico (custo × quantidade na unidade de venda).
  static double contribuicaoValorEstoque(Produto produto) {
    final custo = custoExibicao(produto);
    if (!custo.isFinite || custo < 0 || custo > 1e9) return 0;
    final qtd = ProdutoEmbalagem.valorEstoqueExibicao(
      produto,
      produto.estoqueReal,
    );
    if (!qtd.isFinite || qtd <= 0) return 0;
    final total = qtd * custo;
    if (!total.isFinite || total < 0) return 0;
    // Protege KPI contra cadastro importado absurdo (qtd×custo).
    if (total > 1e12) return 0;
    return total;
  }

  /// Ativo com estoque (unidade de venda) no ou abaixo do minimo cadastrado.
  static bool abaixoDoMinimo(Produto produto) {
    if (!produto.ativo) return false;
    final min = produto.quantidadeMinima;
    if (min < 0) return false;
    return produto.estoqueExibicao <= min + 1e-9;
  }

  /// Estoque reservado somado em unidade de venda (arredondado para KPI).
  static int estoqueReservadoExibicaoArredondado(Produto produto) {
    final v = ProdutoEmbalagem.valorEstoqueExibicao(
      produto,
      produto.estoqueReservado,
    );
    if (!v.isFinite || v <= 0) return 0;
    return v.round().clamp(0, 1 << 30);
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

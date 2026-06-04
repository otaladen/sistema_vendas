import '../model/produto.dart';
import 'quantidade_venda_util.dart';

/// Regras de conversao entre unidade de compra/embalagem e unidade de estoque/venda.
class ProdutoEmbalagem {
  ProdutoEmbalagem._();

  static String normalizarUnidade(String? unidade) {
    final t = (unidade ?? '').trim().toUpperCase();
    if (t.isEmpty) return 'UN';
    if (t == 'METRO') return 'M';
    return t;
  }

  static bool unidadesEquivalentes(String? a, String? b) {
    return normalizarUnidade(a) == normalizarUnidade(b);
  }

  /// Ha fator de embalagem configurado (diferente de 1:1).
  static bool temConversao(Produto produto) {
    final f = produto.quantidadePorEmbalagem;
    return f > 0 && (f - 1).abs() > 0.0001;
  }

  /// Unidade de compra distinta da de venda com conversao ativa.
  static bool vendaPodeUsarUnidadeCompra(Produto produto) {
    if (!temConversao(produto)) return false;
    return !unidadesEquivalentes(
      produto.unidadeCompraEfetiva,
      produto.unidade,
    );
  }

  /// Fator sugerido na conferencia NF-e quando a unidade da nota bate com o cadastro.
  static double? fatorSugeridoNotaParaEstoque({
    required Produto produto,
    required String unidadeNota,
  }) {
    if (!temConversao(produto)) return null;
    final uNota = normalizarUnidade(unidadeNota);
    final uVenda = normalizarUnidade(produto.unidade);
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    if (!unidadesEquivalentes(uNota, uCompra) &&
        !unidadesEquivalentes(uNota, uVenda)) {
      return null;
    }
    return produto.quantidadePorEmbalagem > 0
        ? produto.quantidadePorEmbalagem
        : 1;
  }

  /// Quantidade da nota convertida para unidade de estoque ([Produto.unidade]).
  static int quantidadeNotaParaEstoque({
    required double quantidadeComercial,
    required double fator,
    required bool embalagemMultiplica,
  }) {
    if (fator <= 0 || !quantidadeComercial.isFinite || quantidadeComercial < 0) {
      return 0;
    }
    final bruto = embalagemMultiplica
        ? quantidadeComercial * fator
        : quantidadeComercial / fator;
    if (!bruto.isFinite) return 0;
    return bruto.round();
  }

  /// Quantidade digitada no PDV convertida para estoque.
  static int quantidadeVendaParaEstoque({
    required Produto produto,
    required int quantidadeDigitada,
    required bool emUnidadeCompra,
  }) {
    if (quantidadeDigitada <= 0) return 0;
    if (!emUnidadeCompra || !vendaPodeUsarUnidadeCompra(produto)) {
      return quantidadeDigitada;
    }
    return quantidadeNotaParaEstoque(
      quantidadeComercial: quantidadeDigitada.toDouble(),
      fator: produto.quantidadePorEmbalagem,
      embalagemMultiplica: produto.embalagemMultiplica,
    );
  }

  /// Texto curto para UI (ex.: "1 CX = 12 UN").
  static String rotuloConversao(Produto produto) {
    final fator = produto.quantidadePorEmbalagem;
    if (fator <= 0 || (fator - 1).abs() < 0.0001) return '';
    final fatorTxt = fator == fator.roundToDouble()
        ? fator.toInt().toString()
        : fator.toStringAsFixed(2);
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    final uVenda = normalizarUnidade(produto.unidade);
    if (uCompra == uVenda) {
      return produto.embalagemMultiplica
          ? 'Fator $fatorTxt $uVenda por embalagem'
          : 'Fator $fatorTxt $uVenda por embalagem (divide)';
    }
    return produto.embalagemMultiplica
        ? '1 $uCompra = $fatorTxt $uVenda'
        : '1 $uCompra = 1 $uVenda (÷ $fatorTxt)';
  }

  /// Linha do carrinho PDV com unidade de compra.
  static String rotuloQuantidadeCarrinho({
    required Produto produto,
    required int quantidadeDigitada,
    required bool emUnidadeCompra,
  }) {
    final uVenda = normalizarUnidade(produto.unidade);
    final qEstoque = quantidadeVendaParaEstoque(
      produto: produto,
      quantidadeDigitada: quantidadeDigitada,
      emUnidadeCompra: emUnidadeCompra,
    );
    if (!emUnidadeCompra || !vendaPodeUsarUnidadeCompra(produto)) {
      if (produto.permiteQuantidadeFracionada) {
        final qTxt = QuantidadeVendaUtil.formatarExibicao(
          QuantidadeVendaUtil.valorExibicao(
            quantidadeDigitada,
            fracionada: true,
          ),
          fracionada: true,
        );
        return '$qTxt $uVenda';
      }
      return '$quantidadeDigitada $uVenda';
    }
    final uCompra = normalizarUnidade(produto.unidadeCompraEfetiva);
    return '$quantidadeDigitada $uCompra (= $qEstoque $uVenda)';
  }
}

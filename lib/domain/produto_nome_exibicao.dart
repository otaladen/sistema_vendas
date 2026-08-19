import '../model/item_venda.dart';
import '../model/produto.dart';

/// Nome do produto na tela (busca/PDV) vs na impressao e XML fiscal.
abstract final class ProdutoNomeExibicao {
  ProdutoNomeExibicao._();

  /// Cadastro, PDV, entregas, relatorios.
  static String paraTela(Produto produto) => produto.nome.trim();

  /// Valor gravado no cadastro: nunca vazio apos salvar (padrao = [nome]).
  static String normalizarNomeImpressaoPersistido({
    required String nome,
    required String nomeImpressao,
  }) {
    final n = nome.trim();
    final ni = nomeImpressao.trim();
    if (n.isEmpty) return ni;
    if (ni.isEmpty) return n;
    return ni;
  }

  /// Cupom, orcamento impresso, NFC-e/NF-e (descricao do item).
  static String paraImpressao(Produto produto) {
    return normalizarNomeImpressaoPersistido(
      nome: produto.nome,
      nomeImpressao: produto.nomeImpressao,
    );
  }

  /// Verdadeiro quando o texto de impressao ainda segue o nome do cadastro.
  static bool nomeImpressaoVinculadoAoNome(Produto produto) {
    final n = produto.nome.trim();
    final ni = produto.nomeImpressao.trim();
    return ni.isEmpty || ni == n;
  }

  /// Linha da venda: usa produto vinculado; senao o snapshot [ItemVenda.nomeProduto].
  static String paraImpressaoItem(ItemVenda item) {
    Produto? p;
    try {
      p = item.produto.target;
    } catch (_) {
      p = null;
    }
    if (p != null) return paraImpressao(p);
    final snap = item.nomeProduto.trim();
    return snap.isEmpty ? 'Produto' : snap;
  }
}

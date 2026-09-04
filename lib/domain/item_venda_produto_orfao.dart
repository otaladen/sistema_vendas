import '../model/item_venda.dart';
import '../model/produto.dart';

/// Itens de venda cujo [ItemVenda.produto] aponta para cadastro inexistente.
abstract final class ItemVendaProdutoOrfaoHelper {
  ItemVendaProdutoOrfaoHelper._();

  static bool itemSemProdutoVinculado(
    ItemVenda item, {
    Produto? Function(int id)? obterProduto,
  }) {
    Produto? ligado;
    try {
      ligado = item.produto.target;
    } catch (_) {}
    if (ligado != null) return false;

    final pid = item.produto.targetId;
    if (pid <= 0) return true;
    if (obterProduto != null) {
      return obterProduto(pid) == null;
    }
    return true;
  }

  static List<ItemVenda> filtrarOrfaos(
    Iterable<ItemVenda> itens, {
    required Produto? Function(int id) obterProduto,
  }) {
    return itens
        .where(
          (item) => itemSemProdutoVinculado(
            item,
            obterProduto: obterProduto,
          ),
        )
        .toList();
  }

  static bool pareceErroSemProdutoVinculado(String mensagem) {
    final m = mensagem.toLowerCase();
    return m.contains('sem produto vinculado') ||
        m.contains('sem produto ligado');
  }

  /// Extrai o nome do item de mensagens como
  /// `Item "Areia 1/2m3" sem produto vinculado.`
  static String? nomeItemDoErro(String mensagem) {
    final match = RegExp(
      r'Item\s+"([^"]+)"\s+sem produto',
      caseSensitive: false,
    ).firstMatch(mensagem);
    return match?.group(1)?.trim();
  }
}

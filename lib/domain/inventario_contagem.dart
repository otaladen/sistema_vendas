import '../model/item_inventario.dart';
import '../model/produto.dart';
import 'inventario_constantes.dart';
import 'produto_embalagem.dart';
import 'quantidade_venda_util.dart';

/// Regras de contagem: escala de exibicao, estado e valor estimado.
abstract final class InventarioContagem {
  InventarioContagem._();

  static String estadoDe({
    required bool conferido,
    required int quantidadeContada,
    required int snapshotFisico,
  }) {
    if (!conferido) return InventarioItemEstado.pendente;
    if (quantidadeContada == snapshotFisico) {
      return InventarioItemEstado.conferidoOk;
    }
    return InventarioItemEstado.divergente;
  }

  /// Interpreta quantidade fisica digitada (m², CX, UN), permitindo zero.
  static int? parseQuantidade(String texto, Produto produto) {
    final original = texto.trim();
    if (original.isEmpty) return null;
    var t = original.replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '.');
    }
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0) return null;
    if (v == 0) return 0;
    final fracionada = ProdutoEmbalagem.estoqueUsaEscalaFracionada(produto);
    if (!fracionada) {
      if (v != v.roundToDouble()) return null;
      return v.round();
    }
    return QuantidadeVendaUtil.paraArmazenamento(v, fracionada: true);
  }

  static Produto contextoProduto(ItemInventario item, Produto? live) {
    return live ?? item.comoProdutoStub();
  }

  static String formatarQtd(
    ItemInventario item,
    int armazenado, {
    Produto? live,
    bool detalhado = false,
  }) {
    final ctx = contextoProduto(item, live);
    if (detalhado) {
      return ProdutoEmbalagem.formatarEstoqueDetalhado(ctx, armazenado);
    }
    return ProdutoEmbalagem.formatarEstoque(ctx, armazenado, comUnidade: true);
  }

  static double custoUnitarioDe(Produto produto) {
    if (produto.custoMedio > 0) return produto.custoMedio;
    if (produto.precoCusto > 0) return produto.precoCusto;
    return 0;
  }

  /// Valor estimado da diferenca (unidade de venda × custo).
  static double valorDiferencaAbs(
    ItemInventario item,
    int deltaArmazenado, {
    Produto? live,
  }) {
    if (deltaArmazenado == 0) return 0;
    final custo = item.custoUnitario;
    if (custo <= 0) return 0;
    final ctx = contextoProduto(item, live);
    final qtd = ProdutoEmbalagem.valorEstoqueExibicao(
      ctx,
      deltaArmazenado.abs(),
    );
    if (!qtd.isFinite || qtd <= 0) return 0;
    return qtd * custo;
  }

  static bool itemCombinaBusca(ItemInventario item, String busca) {
    final t = busca.trim().toLowerCase();
    if (t.isEmpty) return true;
    if (item.codigoBarras.trim().toLowerCase() == t) return true;
    if (item.codigoInterno.trim().toLowerCase() == t) return true;
    if (item.nomeSnapshot.toLowerCase().contains(t)) return true;
    if (item.codigoInterno.toLowerCase().contains(t)) return true;
    if (item.codigoBarras.toLowerCase().contains(t)) return true;
    return false;
  }

  static bool itemNoFiltro(ItemInventario item, String filtro) {
    switch (filtro) {
      case InventarioFiltroLista.faltaContar:
        return item.estado == InventarioItemEstado.pendente;
      case InventarioFiltroLista.conferidosOk:
        return item.estado == InventarioItemEstado.conferidoOk;
      case InventarioFiltroLista.divergentes:
        return item.estado == InventarioItemEstado.divergente;
      default:
        return true;
    }
  }
}

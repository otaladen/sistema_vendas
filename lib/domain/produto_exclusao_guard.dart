import '../data/objectbox.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'fiscal/venda_nfce_obrigatoria_helper.dart';
import 'venda_documento_rotulo_helper.dart';

/// Venda finalizada que ainda exige emissao de NFC-e e contem o produto.
class ProdutoExclusaoBloqueio {
  const ProdutoExclusaoBloqueio({
    required this.quantidadeVendas,
    required this.rotulosVendas,
  });

  final int quantidadeVendas;
  final List<String> rotulosVendas;

  String get mensagem {
    if (quantidadeVendas <= 0) return '';
    final visiveis = rotulosVendas.take(3).toList();
    final rotulos = visiveis.join(', ');
    final restante = quantidadeVendas - visiveis.length;
    final sufixo = restante > 0 ? ' e mais $restante' : '';
    return 'Nao e possivel excluir: o produto esta em $quantidadeVendas '
        'venda(s) com NFC-e pendente ($rotulos$sufixo). '
        'Emita a nota em Notas Fiscais ou desative o produto em vez de apagar.';
  }
}

class ProdutoExclusaoBloqueadaException implements Exception {
  ProdutoExclusaoBloqueadaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Impede exclusao de produto usado em vendas com NFC-e ainda nao emitida.
abstract final class ProdutoExclusaoGuard {
  ProdutoExclusaoGuard._();

  static ProdutoExclusaoBloqueio? analisar(
    ObjectBox db,
    int produtoId, {
    int limiteRotulos = 5,
  }) {
    if (produtoId <= 0) return null;
    final qItens = db.itemVendaBox
        .query(ItemVenda_.produto.equals(produtoId))
        .build();
    try {
      final itens = qItens.find();
      if (itens.isEmpty) return null;

      final vendaIds = <int>{};
      for (final item in itens) {
        try {
          final vid = item.venda.targetId;
          if (vid > 0) vendaIds.add(vid);
        } catch (_) {}
      }
      if (vendaIds.isEmpty) return null;

      final pendentes = <Venda>[];
      for (final vid in vendaIds) {
        final venda = db.vendaBox.get(vid);
        if (venda != null && VendaNfceObrigatoriaHelper.ehPendenteEmissao(venda)) {
          pendentes.add(venda);
        }
      }
      if (pendentes.isEmpty) return null;

      pendentes.sort((a, b) => b.id.compareTo(a.id));
      return ProdutoExclusaoBloqueio(
        quantidadeVendas: pendentes.length,
        rotulosVendas: pendentes
            .take(limiteRotulos)
            .map(VendaDocumentoRotuloHelper.rotuloControleInterno)
            .toList(),
      );
    } finally {
      qItens.close();
    }
  }

  static String? mensagemBloqueio(ObjectBox db, int produtoId) =>
      analisar(db, produtoId)?.mensagem;

  static void garantirPodeExcluir(ObjectBox db, int produtoId) {
    final msg = mensagemBloqueio(db, produtoId);
    if (msg != null) {
      throw ProdutoExclusaoBloqueadaException(msg);
    }
  }
}

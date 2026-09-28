/// Reatribui SKU numerico sequencial a produtos cadastrados pela importacao
/// de NF-e com o codigo legado `NFE-<chave>-<item>`.
///
/// So o [Produto.codigoInterno] e os [Produto.apelidosBusca] mudam: o id do
/// produto e mantido, entao estoque, lotes, historico de entrada, vinculos de
/// fornecedor e itens de venda continuam apontando para o mesmo cadastro.
library;

import 'dart:async';

import '../../data/objectbox.dart';
import '../../data/produto_busca_util.dart';
import '../../data/sync/sync_dirty_outbox.dart';
import '../../data/sync/sync_write_trigger.dart';
import '../../model/produto.dart';
import '../../objectbox.g.dart';

/// Uma troca de SKU planejada ou aplicada.
class SkuImportadoReatribuicao {
  const SkuImportadoReatribuicao({
    required this.produtoId,
    required this.nomeProduto,
    required this.skuAntigo,
    required this.skuNovo,
    required this.apelidosBuscaNovos,
  });

  final int produtoId;
  final String nomeProduto;
  final String skuAntigo;
  final String skuNovo;
  final String apelidosBuscaNovos;
}

class SanitizarSkusImportadosUtil {
  SanitizarSkusImportadosUtil._();

  static const String prefixoSkuLegadoNfe = 'NFE-';

  static bool skuLegadoImportacaoNfe(String codigoInterno) => codigoInterno
      .trim()
      .toUpperCase()
      .startsWith(prefixoSkuLegadoNfe);

  /// Monta o plano sem gravar nada. Os produtos `NFE-` recebem SKUs em ordem de
  /// id (cadastro mais antigo primeiro), a partir do maior SKU numerico curto.
  ///
  /// [codigosFornecedorPorProduto] (`cProd` dos vinculos de fornecedor) e o SKU
  /// antigo entram em [Produto.apelidosBusca] quando
  /// [manterSkuAntigoComoApelido] for true, para etiquetas/notas antigas
  /// continuarem localizaveis.
  static List<SkuImportadoReatribuicao> planejar(
    Iterable<Produto> produtos, {
    Map<int, List<String>> codigosFornecedorPorProduto = const {},
    bool manterSkuAntigoComoApelido = true,
  }) {
    final todos = produtos.toList();
    final ocupados = todos.map((p) => p.codigoInterno).toList();
    final alvos =
        todos.where((p) => skuLegadoImportacaoNfe(p.codigoInterno)).toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    final plano = <SkuImportadoReatribuicao>[];
    for (final p in alvos) {
      final skuNovo = proximoSkuNumericoSequencial(ocupados);
      ocupados.add(skuNovo);

      var apelidos = p.apelidosBusca;
      for (final cProd
          in codigosFornecedorPorProduto[p.id] ?? const <String>[]) {
        apelidos = apelidosBuscaComCodigoFornecedor(
          apelidos,
          codigoFornecedor: cProd,
          codigoBarras: p.codigoBarras,
        );
      }
      if (manterSkuAntigoComoApelido) {
        apelidos = apelidosBuscaComCodigoFornecedor(
          apelidos,
          codigoFornecedor: p.codigoInterno,
        );
      }

      plano.add(
        SkuImportadoReatribuicao(
          produtoId: p.id,
          nomeProduto: p.nome,
          skuAntigo: p.codigoInterno,
          skuNovo: skuNovo,
          apelidosBuscaNovos: apelidos,
        ),
      );
    }
    return plano;
  }

  /// Planeja a partir do banco e, se [simular] for false, grava em uma unica
  /// transacao. Depois de aplicar, chame `ProdutoRepository.invalidarCacheBusca()`
  /// na instancia em uso para o PDV enxergar os novos SKUs.
  static List<SkuImportadoReatribuicao> aplicar(
    ObjectBox db, {
    bool simular = false,
    bool manterSkuAntigoComoApelido = true,
  }) {
    late List<SkuImportadoReatribuicao> plano;
    db.store.runInTransaction(simular ? TxMode.read : TxMode.write, () {
      plano = planejar(
        db.produtoBox.getAll(),
        codigosFornecedorPorProduto: _codigosFornecedorPorProduto(db),
        manterSkuAntigoComoApelido: manterSkuAntigoComoApelido,
      );
      if (simular) return;
      for (final item in plano) {
        final produto = db.produtoBox.get(item.produtoId);
        if (produto == null) continue;
        produto.codigoInterno = item.skuNovo;
        produto.apelidosBusca = item.apelidosBuscaNovos;
        db.produtoBox.put(produto);
      }
    });

    if (!simular && plano.isNotEmpty) {
      unawaited(SyncDirtyOutbox.registrar(entity: 'produto', entityId: 0));
      notificarAlteracaoParaRede(
        entidade: 'produto',
        entidadeId: 0,
        entidadeIds: plano.map((p) => p.produtoId).toList(),
      );
    }
    return plano;
  }

  static Map<int, List<String>> _codigosFornecedorPorProduto(ObjectBox db) {
    final out = <int, List<String>>{};
    for (final v in db.vinculoFornecedorProdutoBox.getAll()) {
      final produtoId = v.produto.targetId;
      final codigo = v.codigoProdutoFornecedor.trim();
      if (produtoId <= 0 || codigo.isEmpty) continue;
      out.putIfAbsent(produtoId, () => []).add(codigo);
    }
    return out;
  }
}

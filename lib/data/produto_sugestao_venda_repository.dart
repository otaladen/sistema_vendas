import '../model/produto_sugestao_venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class ProdutoSugestaoVendaRepository {
  ProdutoSugestaoVendaRepository(this._db);

  final ObjectBox _db;

  List<ProdutoSugestaoVenda> listarPorProdutoOrigem(
    int produtoOrigemId, {
    bool somenteAtivas = true,
  }) {
    if (produtoOrigemId <= 0) return const [];
    final base = ProdutoSugestaoVenda_.produtoOrigemId.equals(produtoOrigemId);
    final cond = somenteAtivas
        ? base & ProdutoSugestaoVenda_.ativo.equals(true)
        : base;
    final q = _db.produtoSugestaoVendaBox
        .query(cond)
        .order(ProdutoSugestaoVenda_.prioridade)
        .order(ProdutoSugestaoVenda_.id)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Substitui todas as sugestoes do produto origem (cadastro).
  void substituirDoProduto(
    int produtoOrigemId,
    List<ProdutoSugestaoVenda> sugestoes,
  ) {
    if (produtoOrigemId <= 0) {
      throw ArgumentError('produtoOrigemId invalido.');
    }
    for (final s in sugestoes) {
      if (s.produtoSugeridoId <= 0) {
        throw ArgumentError('Cada sugestao precisa de um produto sugerido.');
      }
      if (s.produtoSugeridoId == produtoOrigemId) {
        throw ArgumentError('Produto nao pode sugerir a si mesmo.');
      }
      if (s.quantidadeSugerida <= 0) {
        throw ArgumentError('Quantidade sugerida deve ser maior que zero.');
      }
    }

    _db.store.runInTransaction(TxMode.write, () {
      _removerPorProdutoOrigemTx(produtoOrigemId);
      for (final s in sugestoes) {
        final linha = ProdutoSugestaoVenda(
          id: 0,
          produtoOrigemId: produtoOrigemId,
          produtoSugeridoId: s.produtoSugeridoId,
          tipo: s.tipo,
          quantidadeSugerida: s.quantidadeSugerida,
          prioridade: s.prioridade,
          observacao: s.observacao,
          ativo: s.ativo,
        );
        _db.produtoSugestaoVendaBox.put(linha);
      }
    });

    notificarAlteracaoParaRede(
      entidade: 'produto_sugestao_venda',
      entidadeId: 0,
    );
  }

  void _removerPorProdutoOrigemTx(int produtoOrigemId) {
    final q = _db.produtoSugestaoVendaBox
        .query(ProdutoSugestaoVenda_.produtoOrigemId.equals(produtoOrigemId))
        .build();
    try {
      _db.produtoSugestaoVendaBox.removeMany(q.findIds());
    } finally {
      q.close();
    }
  }
}

import '../domain/estoque/tipo_movimento_estoque.dart';
import '../model/movimento_estoque.dart';
import '../model/produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Persistencia do kardex de estoque.
class MovimentoEstoqueRepository {
  MovimentoEstoqueRepository(this._db);

  final ObjectBox _db;

  void registrar({
    required Produto produto,
    required TipoMovimentoEstoque tipo,
    required int saldoFisicoAntes,
    required int saldoReservaAntes,
    required int saldoFisicoDepois,
    required int saldoReservaDepois,
    String documentoReferencia = '',
    String motivo = '',
    String usuarioLogin = '',
  }) {
    if (produto.id <= 0) return;
    final deltaFisico = saldoFisicoDepois - saldoFisicoAntes;
    final deltaReserva = saldoReservaDepois - saldoReservaAntes;
    if (deltaFisico == 0 && deltaReserva == 0) return;

    final linha = MovimentoEstoque(
      tipoMovimento: tipo.name,
      deltaFisico: deltaFisico,
      deltaReserva: deltaReserva,
      saldoFisicoAntes: saldoFisicoAntes,
      saldoFisicoDepois: saldoFisicoDepois,
      saldoReservaAntes: saldoReservaAntes,
      saldoReservaDepois: saldoReservaDepois,
      documentoReferencia: documentoReferencia.trim(),
      motivo: motivo.trim(),
      usuarioLogin: usuarioLogin.trim(),
    );
    linha.produto.targetId = produto.id;
    final id = _db.movimentoEstoqueBox.put(linha);
    notificarAlteracaoParaRede(entidade: 'movimento_estoque', entidadeId: id);
  }

  List<MovimentoEstoque> listarPorProduto(
    int produtoId, {
    int limite = 200,
  }) {
    if (produtoId <= 0) return const [];
    final q = _db.movimentoEstoqueBox
        .query(MovimentoEstoque_.produto.equals(produtoId))
        .order(MovimentoEstoque_.registradoEm, flags: Order.descending)
        .build();
    try {
      q.limit = limite;
      return q.find();
    } finally {
      q.close();
    }
  }

  int contarPorProduto(int produtoId) {
    if (produtoId <= 0) return 0;
    final q = _db.movimentoEstoqueBox
        .query(MovimentoEstoque_.produto.equals(produtoId))
        .build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  /// Movimentos no intervalo (UTC), ordenados do mais antigo ao mais recente.
  List<MovimentoEstoque> listarPorPeriodo({
    required DateTime inicio,
    required DateTime fim,
    int? produtoId,
  }) {
    final inicioUtc = DateTime(inicio.year, inicio.month, inicio.day).toUtc();
    final fimUtc = DateTime(
      fim.year,
      fim.month,
      fim.day,
      23,
      59,
      59,
      999,
    ).toUtc();
    var cond = MovimentoEstoque_.registradoEm
        .greaterOrEqualDate(inicioUtc)
        .and(MovimentoEstoque_.registradoEm.lessOrEqualDate(fimUtc));
    if (produtoId != null && produtoId > 0) {
      cond = cond & MovimentoEstoque_.produto.equals(produtoId);
    }
    final q = _db.movimentoEstoqueBox
        .query(cond)
        .order(MovimentoEstoque_.registradoEm)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }
}

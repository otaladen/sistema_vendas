import '../model/kit_orcamento.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class KitOrcamentoRepository {
  KitOrcamentoRepository(this._db);

  final ObjectBox _db;

  List<KitOrcamento> listarPorNome({bool somenteAtivos = false}) {
    late final Query<KitOrcamento> q;
    if (somenteAtivos) {
      q = _db.kitOrcamentoBox
          .query(KitOrcamento_.ativo.equals(true))
          .order(KitOrcamento_.nome)
          .build();
    } else {
      q = _db.kitOrcamentoBox.query().order(KitOrcamento_.nome).build();
    }
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  KitOrcamento? obterPorId(int id) {
    final k = _db.kitOrcamentoBox.get(id);
    if (k == null) return null;
    // Acesso a itens forca carga lazy do ToMany.
    k.itens.length;
    return k;
  }

  /// Kits ativos que contem o produto (consulta PDV / sugestao de composicao).
  List<KitOrcamento> listarAtivosComProduto(int produtoId, {int limite = 3}) {
    if (produtoId <= 0 || limite <= 0) return const [];
    final q = _db.kitOrcamentoItemBox
        .query(KitOrcamentoItem_.produto.equals(produtoId))
        .build();
    try {
      final vistos = <int>{};
      final out = <KitOrcamento>[];
      for (final linha in q.find()) {
        final kitId = linha.kit.targetId;
        if (kitId <= 0 || vistos.contains(kitId)) continue;
        final kit = obterPorId(kitId);
        if (kit == null || !kit.ativo) continue;
        vistos.add(kitId);
        out.add(kit);
        if (out.length >= limite) break;
      }
      return out;
    } finally {
      q.close();
    }
  }

  void salvar(KitOrcamento kit, List<KitOrcamentoItem> itens) {
    if (kit.nome.trim().isEmpty) {
      throw ArgumentError('Nome do kit e obrigatorio.');
    }
    for (final it in itens) {
      if (it.quantidade <= 0) {
        throw ArgumentError('Quantidade invalida em item de kit.');
      }
      if (it.produto.targetId == 0) {
        throw ArgumentError('Cada linha do kit deve ter um produto.');
      }
    }

    _db.store.runInTransaction(TxMode.write, () {
      final kitIdExistente = kit.id;
      if (kitIdExistente != 0) {
        _removerItensDoKitTx(kitIdExistente);
      }
      final idKit = _db.kitOrcamentoBox.put(kit);
      kit.id = idKit;
      var ordem = 0;
      for (final it in itens) {
        it.id = 0;
        it.ordem = ordem++;
        it.kit.targetId = idKit;
        _db.kitOrcamentoItemBox.put(it);
      }
    });
    notificarAlteracaoParaRede(
      entidade: 'kit_orcamento',
      entidadeId: kit.id > 0 ? kit.id : 0,
    );
  }

  void _removerItensDoKitTx(int kitId) {
    final q = _db.kitOrcamentoItemBox
        .query(KitOrcamentoItem_.kit.equals(kitId))
        .build();
    try {
      final ids = q.findIds();
      for (final id in ids) {
        _db.kitOrcamentoItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }

  bool remover(int id) {
    var ok = false;
    _db.store.runInTransaction(TxMode.write, () {
      _removerItensDoKitTx(id);
      ok = _db.kitOrcamentoBox.remove(id);
    });
    if (ok) {
      registrarDeleteParaRede('kit_orcamento', id);
    }
    return ok;
  }
}

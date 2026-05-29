import '../domain/promocao_cadastro.dart';
import '../domain/promocao_info_vigente.dart';
import '../domain/promocao_preco_service.dart';
import '../model/produto.dart';
import '../model/promocao.dart';
import '../model/promocao_combo_item.dart';
import '../model/promocao_item.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class PromocaoRepository {
  PromocaoRepository(this._db);

  final ObjectBox _db;

  List<Promocao> listarPorNome() {
    final q = _db.promocaoBox.query().order(Promocao_.nome).build();
    try {
      final lista = q.find();
      for (final p in lista) {
        p.itens.length;
        p.comboItens.length;
      }
      return lista;
    } finally {
      q.close();
    }
  }

  List<Promocao> listarVigentesNaData(DateTime data) {
    final local = DateTime(data.year, data.month, data.day);
    final inicioDia = DateTime.utc(local.year, local.month, local.day);
    final fimDia = DateTime.utc(
      local.year,
      local.month,
      local.day,
      23,
      59,
      59,
      999,
    );

    final q = _db.promocaoBox.query(Promocao_.ativa.equals(true)).build();
    try {
      final lista = q.find().where((p) {
        final ini = p.dataInicio.toUtc();
        final fim = p.dataFim.toUtc();
        return !ini.isAfter(fimDia) && !fim.isBefore(inicioDia);
      }).toList()
        ..sort((a, b) => b.prioridade.compareTo(a.prioridade));
      for (final p in lista) {
        p.itens.length;
        p.comboItens.length;
      }
      return lista;
    } finally {
      q.close();
    }
  }

  Promocao? obterPorId(int id) {
    final p = _db.promocaoBox.get(id);
    if (p == null) return null;
    p.itens.length;
    p.comboItens.length;
    return p;
  }

  void salvar(
    Promocao promocao,
    List<PromocaoItem> itens, {
    List<PromocaoComboItem> comboItens = const [],
  }) {
    if (promocao.nome.trim().isEmpty) {
      throw ArgumentError('Nome da promocao e obrigatorio.');
    }
    if (promocao.dataFim.isBefore(promocao.dataInicio)) {
      throw ArgumentError('Data final deve ser igual ou posterior a inicial.');
    }
    final tipo = PromocaoCadastro.normalizarTipoCampanha(promocao.tipoCampanha);
    if (tipo == PromocaoCadastro.tipoComboAb) {
      if (comboItens.isEmpty) {
        throw ArgumentError('Combo A+B precisa de ao menos um produto.');
      }
      if (promocao.precoCombo <= 0) {
        throw ArgumentError('Informe o preco fechado do combo.');
      }
    } else if (itens.isEmpty) {
      throw ArgumentError('Inclua ao menos um produto ou categoria na promocao.');
    }
    for (final it in itens) {
      if (it.produtoAlvoId <= 0 &&
          it.categoria.trim().isEmpty &&
          it.subcategoria.trim().isEmpty) {
        throw ArgumentError(
          'Cada linha deve ter produto ou categoria/subcategoria.',
        );
      }
      if (it.quantidadeMinima < 1) {
        throw ArgumentError('Quantidade minima invalida.');
      }
    }

    _db.store.runInTransaction(TxMode.write, () {
      final idExistente = promocao.id;
      if (idExistente != 0) {
        _removerItensPromocaoTx(idExistente);
        _removerComboItensTx(idExistente);
      }
      final idPromo = _db.promocaoBox.put(promocao);
      promocao.id = idPromo;
      var ordem = 0;
      for (final it in itens) {
        it.id = 0;
        it.ordem = ordem++;
        it.promocao.targetId = idPromo;
        _db.promocaoItemBox.put(it);
      }
      ordem = 0;
      for (final c in comboItens) {
        c.id = 0;
        c.ordem = ordem++;
        c.promocao.targetId = idPromo;
        _db.promocaoComboItemBox.put(c);
      }
    });
    notificarAlteracaoParaRede(
      entidade: 'promocao',
      entidadeId: promocao.id > 0 ? promocao.id : 0,
    );
  }

  void registrarVendaPromocao(int promocaoId, int quantidade) {
    if (promocaoId <= 0 || quantidade <= 0) return;
    _db.store.runInTransaction(TxMode.write, () {
      final p = _db.promocaoBox.get(promocaoId);
      if (p == null) return;
      p.quantidadeVendidaPromo += quantidade;
      _db.promocaoBox.put(p);
    });
    notificarAlteracaoParaRede(
      entidade: 'promocao',
      entidadeId: promocaoId,
    );
  }

  /// Produtos com campanha vigente (para etiquetas de gondola).
  List<({Produto produto, PromocaoInfoVigente info})> listarProdutosEtiquetaGondola(
    DateTime data, {
    Produto? Function(int id)? obterProduto,
  }) {
    final svc = PromocaoPrecoService(this);
    final out = <({Produto produto, PromocaoInfoVigente info})>[];
    final vistos = <int>{};
    for (final promo in listarVigentesNaData(data)) {
      if (PromocaoCadastro.normalizarTipoCampanha(promo.tipoCampanha) ==
          PromocaoCadastro.tipoComboAb) {
        continue;
      }
      promo.itens.length;
      for (final it in promo.itens) {
        if (it.produtoAlvoId <= 0 || vistos.contains(it.produtoAlvoId)) continue;
        final p = obterProduto?.call(it.produtoAlvoId) ??
            _db.produtoBox.get(it.produtoAlvoId);
        if (p == null || !p.ativo) continue;
        vistos.add(p.id);
        final infos = svc.listarCampanhasVigentesParaProduto(p, dataReferencia: data);
        if (infos.isEmpty) continue;
        out.add((produto: p, info: infos.first));
      }
    }
    out.sort((a, b) => a.produto.nome.compareTo(b.produto.nome));
    return out;
  }

  void excluir(int id) {
    _db.store.runInTransaction(TxMode.write, () {
      _removerItensPromocaoTx(id);
      _removerComboItensTx(id);
      _db.promocaoBox.remove(id);
    });
    notificarAlteracaoParaRede(
      entidade: 'promocao',
      entidadeId: id,
    );
  }

  void _removerItensPromocaoTx(int promocaoId) {
    final q = _db.promocaoItemBox
        .query(PromocaoItem_.promocao.equals(promocaoId))
        .build();
    try {
      for (final id in q.findIds()) {
        _db.promocaoItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }

  void _removerComboItensTx(int promocaoId) {
    final q = _db.promocaoComboItemBox
        .query(PromocaoComboItem_.promocao.equals(promocaoId))
        .build();
    try {
      for (final id in q.findIds()) {
        _db.promocaoComboItemBox.remove(id);
      }
    } finally {
      q.close();
    }
  }
}

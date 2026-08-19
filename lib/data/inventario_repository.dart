import '../domain/inventario_codec.dart';
import '../domain/inventario_constantes.dart';
import '../domain/inventario_contagem.dart';
import '../model/item_inventario.dart';
import '../model/produto.dart';
import '../model/sessao_inventario.dart';
import '../objectbox.g.dart';
import 'inventario_gateway.dart';
import 'objectbox.dart';
import 'produto_repository.dart';
import 'sync/sync_write_trigger.dart';

/// Persistencia ObjectBox do balanco (PC servidor).
class InventarioRepository implements InventarioGateway {
  InventarioRepository(this._db, [ProdutoRepository? produtos])
      : _produtos = produtos ?? ProdutoRepository(_db);

  final ObjectBox _db;
  final ProdutoRepository _produtos;

  Box<SessaoInventario> get _sessoes => _db.sessaoInventarioBox;
  Box<ItemInventario> get _itens => _db.itemInventarioBox;

  @override
  Future<List<SessaoInventario>> listarSessoes() async {
    final list = _sessoes.getAll();
    final canceladas = list
        .where((s) => s.status == InventarioSessaoStatus.cancelada)
        .toList();
    for (final s in canceladas) {
      _apagarSessaoEItens(s.id);
    }
    final vivas = list
        .where((s) => s.status != InventarioSessaoStatus.cancelada)
        .toList();
    vivas.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
    return vivas;
  }

  @override
  Future<SessaoInventario?> obterSessao(int id) async {
    if (id <= 0) return null;
    return _sessoes.get(id);
  }

  List<Produto> _produtosDoFiltro({
    String categoria = '',
    String subcategoria = '',
  }) {
    final cat = categoria.trim();
    final sub = subcategoria.trim();
    final todos = _produtos.listarTodos(somenteAtivos: true);
    if (cat.isEmpty && sub.isEmpty) return todos;
    return todos.where((p) {
      if (cat.isNotEmpty &&
          p.categoria.trim().toLowerCase() != cat.toLowerCase()) {
        return false;
      }
      if (sub.isNotEmpty &&
          p.subcategoria.trim().toLowerCase() != sub.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<InventarioCategoriasInfo> obterCategorias() async {
    final produtos = _produtos.listarTodos(somenteAtivos: true);
    final cats = <String>{};
    final subPorCat = <String, Set<String>>{};
    for (final p in produtos) {
      final c = p.categoria.trim();
      if (c.isEmpty) continue;
      cats.add(c);
      final sub = p.subcategoria.trim();
      if (sub.isEmpty) continue;
      (subPorCat[c] ??= <String>{}).add(sub);
    }
    final ordenadas = cats.toList()..sort();
    final mapa = <String, List<String>>{};
    for (final c in ordenadas) {
      final subs = subPorCat[c]?.toList() ?? <String>[];
      subs.sort();
      mapa[c] = subs;
    }
    return InventarioCategoriasInfo(
      categorias: ordenadas,
      subcategoriasPorCategoria: mapa,
      totalAtivos: produtos.length,
    );
  }

  @override
  Future<int> contarProdutosNoFiltro({
    String categoria = '',
    String subcategoria = '',
  }) async {
    return _produtosDoFiltro(
      categoria: categoria,
      subcategoria: subcategoria,
    ).length;
  }

  @override
  Future<SessaoInventario> criarSessao({
    required String nome,
    String categoria = '',
    String subcategoria = '',
    bool contagemCega = false,
    String criadoPor = '',
  }) async {
    final nomeNorm = nome.trim();
    if (nomeNorm.isEmpty) {
      throw StateError('Informe o nome da sessao de inventario.');
    }
    final produtos = _produtosDoFiltro(
      categoria: categoria,
      subcategoria: subcategoria,
    );
    if (produtos.isEmpty) {
      throw StateError(
        'Nenhum produto ativo no filtro selecionado para iniciar o balanco.',
      );
    }

    final sessao = SessaoInventario(
      nome: nomeNorm,
      filtroCategoria: categoria.trim(),
      filtroSubcategoria: subcategoria.trim(),
      contagemCega: contagemCega,
      criadoPor: criadoPor.trim(),
      totalItens: produtos.length,
    );
    _db.store.runInTransaction(TxMode.write, () {
      _sessoes.put(sessao);
      final linhas = <ItemInventario>[];
      for (final p in produtos) {
        final livre = p.estoqueLivreParaVenda;
        linhas.add(
          ItemInventario(
            sessaoId: sessao.id,
            produtoId: p.id,
            nomeSnapshot: p.nome,
            codigoInterno: p.codigoInterno,
            codigoBarras: p.codigoBarras,
            unidade: p.unidade,
            categoria: p.categoria,
            subcategoria: p.subcategoria,
            permiteQuantidadeFracionada: p.permiteQuantidadeFracionada,
            quantidadePorEmbalagem: p.quantidadePorEmbalagem,
            embalagemMultiplica: p.embalagemMultiplica,
            unidadeCompra: p.unidadeCompra,
            controlaLoteValidade: p.controlaLoteValidade,
            snapshotFisico: p.estoqueReal,
            snapshotLivre: livre < 0 ? 0 : livre,
            snapshotReservado: p.estoqueReservado,
            custoUnitario: InventarioContagem.custoUnitarioDe(p),
          ),
        );
      }
      _itens.putMany(linhas);
    });
    _avisarRede(sessao.id);
    return sessao;
  }

  @override
  Future<SessaoInventario> definirContagemCega({
    required int sessaoId,
    required bool contagemCega,
  }) async {
    final sessao = _exigirSessaoAberta(sessaoId);
    sessao.contagemCega = contagemCega;
    _sessoes.put(sessao);
    _avisarRede(sessao.id);
    return sessao;
  }

  List<ItemInventario> _itensDaSessao(int sessaoId) {
    final q = _itens.query(ItemInventario_.sessaoId.equals(sessaoId)).build();
    try {
      final list = q.find();
      list.sort(
        (a, b) => a.nomeSnapshot.toLowerCase().compareTo(
              b.nomeSnapshot.toLowerCase(),
            ),
      );
      return list;
    } finally {
      q.close();
    }
  }

  @override
  Future<List<ItemInventario>> listarItens(
    int sessaoId, {
    String filtro = 'todos',
    String busca = '',
  }) async {
    return _itensDaSessao(sessaoId)
        .where(
          (i) =>
              InventarioContagem.itemNoFiltro(i, filtro) &&
              InventarioContagem.itemCombinaBusca(i, busca),
        )
        .toList();
  }

  @override
  Future<ItemInventario> registrarContagem({
    required int sessaoId,
    required int itemId,
    required int quantidadeArmazenada,
    String usuarioLogin = '',
  }) async {
    if (quantidadeArmazenada < 0) {
      throw StateError('Quantidade fisica nao pode ser negativa.');
    }
    final sessao = _exigirSessaoAberta(sessaoId);
    final item = _itens.get(itemId);
    if (item == null || item.sessaoId != sessaoId) {
      throw StateError('Item de inventario nao encontrado.');
    }
    if (item.aplicado) {
      throw StateError(
        'Este item ja teve ajuste aplicado. Nao e possivel recontar.',
      );
    }
    item.quantidadeContada = quantidadeArmazenada;
    item.conferido = true;
    item.conferidoPor = usuarioLogin.trim();
    item.conferidoEm = DateTime.now().toUtc();
    item.aplicarEstadoDaContagem();
    _itens.put(item);
    _recalcularTotais(sessao);
    _sessoes.put(sessao);
    _avisarRede(sessao.id);
    return item;
  }

  @override
  Future<InventarioAplicacaoResultado> aplicarAjustes({
    required int sessaoId,
    String usuarioLogin = '',
  }) async {
    final sessao = _exigirSessaoAberta(sessaoId);
    final itens = _itensDaSessao(sessaoId);
    final divergentes = itens
        .where(
          (i) =>
              i.estado == InventarioItemEstado.divergente && !i.aplicado,
        )
        .toList();
    final falhas = <InventarioAplicacaoFalha>[];
    var aplicados = 0;
    final motivo = 'Ajuste por Inventário - Sessão #${sessao.id}';
    final login = usuarioLogin.trim();

    for (final item in divergentes) {
      try {
        _produtos.ajustarEstoqueManual(
          produtoId: item.produtoId,
          novaQuantidadeFisica: item.quantidadeContada,
          motivo: motivo,
          usuarioLogin: login,
        );
        item.aplicado = true;
        _itens.put(item);
        aplicados++;
      } catch (e) {
        falhas.add(
          InventarioAplicacaoFalha(
            itemId: item.id,
            produtoId: item.produtoId,
            nome: item.nomeSnapshot,
            erro: '$e',
          ),
        );
      }
    }

    if (falhas.isEmpty) {
      sessao.status = InventarioSessaoStatus.aplicada;
      sessao.aplicadaEm = DateTime.now().toUtc();
      sessao.aplicadaPor = login;
    }
    _recalcularTotais(sessao);
    _sessoes.put(sessao);
    _avisarRede(sessao.id);
    return InventarioAplicacaoResultado(
      sessao: sessao,
      aplicados: aplicados,
      falhas: falhas,
    );
  }

  @override
  Future<SessaoInventario> cancelarSessao({
    required int sessaoId,
    String usuarioLogin = '',
  }) async {
    final sessao = _sessoes.get(sessaoId);
    if (sessao == null) {
      throw StateError('Sessao de inventario #$sessaoId nao encontrada.');
    }
    if (sessao.status == InventarioSessaoStatus.aplicada) {
      throw StateError(
        'Sessao ja aplicada nao pode ser apagada (o estoque ja foi ajustado).',
      );
    }
    sessao.status = InventarioSessaoStatus.cancelada;
    sessao.aplicadaPor = usuarioLogin.trim();
    sessao.aplicadaEm = DateTime.now().toUtc();
    _apagarSessaoEItens(sessao.id);
    _avisarRede(sessao.id);
    return sessao;
  }

  void _apagarSessaoEItens(int sessaoId) {
    final q = _itens.query(ItemInventario_.sessaoId.equals(sessaoId)).build();
    try {
      _itens.removeMany(q.findIds());
    } finally {
      q.close();
    }
    _sessoes.remove(sessaoId);
  }

  @override
  Produto? produtoDe(ItemInventario item) {
    if (item.produtoId <= 0) return null;
    return _produtos.obterPorId(item.produtoId);
  }

  ItemInventario? obterItem(int id) => id > 0 ? _itens.get(id) : null;

  SessaoInventario _exigirSessaoAberta(int sessaoId) {
    final sessao = _sessoes.get(sessaoId);
    if (sessao == null) {
      throw StateError('Sessao de inventario #$sessaoId nao encontrada.');
    }
    if (!sessao.aberta) {
      throw StateError(
        'Sessao "${sessao.nome}" nao esta aberta '
        '(${InventarioSessaoStatus.rotulo(sessao.status)}).',
      );
    }
    return sessao;
  }

  void _recalcularTotais(SessaoInventario sessao) {
    final itens = _itensDaSessao(sessao.id);
    sessao.totalItens = itens.length;
    sessao.totalConferidos = itens.where((i) => i.conferido).length;
    sessao.totalDivergentes =
        itens.where((i) => i.estado == InventarioItemEstado.divergente).length;
    var sobras = 0.0;
    var perdas = 0.0;
    for (final i in itens) {
      if (!i.conferido) continue;
      final delta = i.deltaArmazenado;
      if (delta == 0) continue;
      final v = InventarioContagem.valorDiferencaAbs(i, delta);
      if (delta > 0) {
        sobras += v;
      } else {
        perdas += v;
      }
    }
    sessao.valorSobras = sobras;
    sessao.valorPerdas = perdas;
  }

  void _avisarRede(int sessaoId) {
    notificarAlteracaoParaRede(entidade: 'inventario', entidadeId: sessaoId);
  }
}

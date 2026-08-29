import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lista_compra_entrada_nfe_linha.dart';
import '../domain/lista_compra_item_constantes.dart';
import '../model/item_lista_compra.dart';
import '../model/produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sugestao_compra_repository.dart';
import 'sync/sync_write_trigger.dart';

/// Agrupamento de itens ativos por fornecedor (Fase 3).
class ListaCompraGrupoFornecedor {
  const ListaCompraGrupoFornecedor({
    required this.fornecedor,
    required this.itens,
    required this.valorEstimado,
  });

  final String fornecedor;
  final List<ItemListaCompra> itens;
  final double valorEstimado;
}

/// CRUD e regras da lista de compras.
class ListaCompraRepository {
  ListaCompraRepository(this._db);

  final ObjectBox _db;

  static const _prefsIgnorados = 'lista_compra_sugestoes_ignoradas_v1';

  Box<ItemListaCompra> get _box => _db.itemListaCompraBox;

  List<ItemListaCompra> listarTodos() {
    final itens = _box.getAll();
    itens.sort(_compararItens);
    return itens;
  }

  List<ItemListaCompra> listarAtivos() {
    return listarTodos().where((i) => i.ativo).toList();
  }

  List<ItemListaCompra> listarPorStatus(String status) {
    return listarTodos().where((i) => i.status == status).toList();
  }

  int contarAtivos({bool apenasUrgentes = false}) {
    final q = _box.query().build();
    try {
      final todos = q.find().where((i) => i.ativo);
      if (!apenasUrgentes) return todos.length;
      return todos
          .where((i) => i.prioridade == ListaCompraItemPrioridade.urgente)
          .length;
    } finally {
      q.close();
    }
  }

  ItemListaCompra? obterPorId(int id) => id > 0 ? _box.get(id) : null;

  Produto? produtoDe(ItemListaCompra item) {
    final ligado = item.produto.target;
    if (ligado != null) return ligado;
    final id = item.produtoId;
    if (id <= 0) return null;
    return _db.produtoBox.get(id);
  }

  /// Anota ou incrementa item pendente do mesmo produto.
  ItemListaCompra anotar({
    Produto? produto,
    String descricaoLivre = '',
    required int quantidadeSugerida,
    String unidade = 'UN',
    String fornecedorTexto = '',
    String prioridade = ListaCompraItemPrioridade.normal,
    String observacao = '',
    String origem = ListaCompraItemOrigem.manual,
    String criadoPor = '',
  }) {
    if (quantidadeSugerida <= 0) {
      throw ArgumentError('Quantidade deve ser maior que zero.');
    }
    final pid = produto?.id ?? 0;
    final nomeLivre = descricaoLivre.trim();
    if (pid <= 0 && nomeLivre.isEmpty) {
      throw ArgumentError('Informe produto ou descricao.');
    }

    ItemListaCompra? existente;
    if (pid > 0) {
      existente = _buscarPendentePorProdutoId(pid);
    }

    if (existente != null) {
      existente.quantidadeSugerida += quantidadeSugerida;
      if (observacao.trim().isNotEmpty) {
        final ant = existente.observacao.trim();
        existente.observacao = ant.isEmpty
            ? observacao.trim()
            : '$ant | ${observacao.trim()}';
      }
      if (prioridade == ListaCompraItemPrioridade.urgente) {
        existente.prioridade = prioridade;
      }
      if (fornecedorTexto.trim().isNotEmpty &&
          existente.fornecedorTexto.trim().isEmpty) {
        existente.fornecedorTexto = fornecedorTexto.trim();
      }
      final id = _box.put(existente);
      existente.id = id;
      _notificar(id);
      return existente;
    }

    final fornecedor = fornecedorTexto.trim().isNotEmpty
        ? fornecedorTexto.trim()
        : (produto?.fornecedor.trim() ?? '');

    final item = ItemListaCompra(
      descricaoLivre: pid > 0 ? '' : nomeLivre,
      quantidadeSugerida: quantidadeSugerida,
      unidade: unidade.trim().isNotEmpty
          ? unidade.trim().toUpperCase()
          : (produto?.unidade ?? 'UN'),
      fornecedorTexto: fornecedor,
      prioridade: prioridade,
      observacao: observacao.trim(),
      origem: origem,
      criadoPor: criadoPor.trim(),
    );
    if (pid > 0) {
      item.produto.target = produto;
    }
    final id = _box.put(item);
    item.id = id;
    _notificar(id);
    return item;
  }

  ItemListaCompra aceitarSugestaoSistema({
    required LinhaSugestaoCompra linha,
    String criadoPor = '',
    int? quantidadeOverride,
  }) {
    final qtd = quantidadeOverride ?? linha.quantidadeSugerida;
    return anotar(
      produto: linha.produto,
      quantidadeSugerida: qtd > 0 ? qtd : 1,
      unidade: linha.produto.unidade,
      fornecedorTexto: linha.fornecedorUltimaNfe.trim().isNotEmpty
          ? linha.fornecedorUltimaNfe.trim()
          : linha.produto.fornecedor,
      prioridade: linha.estoqueCritico
          ? ListaCompraItemPrioridade.urgente
          : ListaCompraItemPrioridade.normal,
      observacao: linha.estoqueCritico
          ? 'Sugestao sistema: abaixo do ponto de pedido'
          : 'Sugestao sistema',
      origem: ListaCompraItemOrigem.sistema,
      criadoPor: criadoPor,
    );
  }

  Future<void> ignorarSugestaoSistema(int produtoId) async {
    if (produtoId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final set = await _carregarIgnorados(prefs);
    set.add(produtoId);
    await _salvarIgnorados(prefs, set);
  }

  Future<bool> sugestaoIgnorada(int produtoId) async {
    if (produtoId <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final set = await _carregarIgnorados(prefs);
    return set.contains(produtoId);
  }

  Future<Set<int>> listarProdutosSugestaoIgnorados() async {
    final prefs = await SharedPreferences.getInstance();
    return _carregarIgnorados(prefs);
  }

  List<LinhaSugestaoCompra> listarSugestoesSistemaDisponiveis({
    int diasPeriodo = 60,
    int diasCobertura = 30,
  }) {
    final repo = SugestaoCompraRepository(_db);
    final linhas = repo.montarLinhas(
      diasPeriodoConsumo: diasPeriodo,
      diasCoberturaAlvo: diasCobertura,
      apenasComSugestaoOuRisco: true,
    );
    final ativos = listarAtivos();
    final pidsNaLista = ativos
        .map((i) => i.produtoId)
        .where((id) => id > 0)
        .toSet();

    return linhas.where((l) {
      if (pidsNaLista.contains(l.produto.id)) return false;
      return true;
    }).toList();
  }

  Future<List<LinhaSugestaoCompra>> listarSugestoesSistemaFiltradas({
    int diasPeriodo = 60,
    int diasCobertura = 30,
  }) async {
    final ignorados = await listarProdutosSugestaoIgnorados();
    return listarSugestoesSistemaDisponiveis(
      diasPeriodo: diasPeriodo,
      diasCobertura: diasCobertura,
    ).where((l) => !ignorados.contains(l.produto.id)).toList();
  }

  ItemListaCompra atualizarStatus(int id, String status) {
    final item = obterPorId(id);
    if (item == null) throw StateError('Item $id nao encontrado.');
    item.status = status;
    if (status == ListaCompraItemStatus.recebido ||
        status == ListaCompraItemStatus.cancelado) {
      item.resolvidoEm = DateTime.now().toUtc();
    } else {
      item.resolvidoEm = null;
    }
    _box.put(item);
    _notificar(id);
    return item;
  }

  ItemListaCompra atualizarCampos({
    required int id,
    int? quantidadeSugerida,
    String? observacao,
    String? prioridade,
    String? fornecedorTexto,
    String? status,
  }) {
    final item = obterPorId(id);
    if (item == null) throw StateError('Item $id nao encontrado.');
    if (quantidadeSugerida != null) {
      if (quantidadeSugerida <= 0) {
        throw ArgumentError('Quantidade invalida.');
      }
      item.quantidadeSugerida = quantidadeSugerida;
    }
    if (observacao != null) item.observacao = observacao.trim();
    if (prioridade != null) item.prioridade = prioridade;
    if (fornecedorTexto != null) {
      item.fornecedorTexto = fornecedorTexto.trim();
    }
    if (status != null) {
      item.status = status;
      if (status == ListaCompraItemStatus.recebido ||
          status == ListaCompraItemStatus.cancelado) {
        item.resolvidoEm = DateTime.now().toUtc();
      }
    }
    _box.put(item);
    _notificar(id);
    return item;
  }

  void cancelar(int id) {
    atualizarStatus(id, ListaCompraItemStatus.cancelado);
  }

  int contarFinalizados() {
    return _box.getAll().where((i) => !i.ativo).length;
  }

  int contarPorStatus(String status) {
    return _box.getAll().where((i) => i.status == status).length;
  }

  /// Remove um item do historico (exclui do banco).
  void remover(int id) {
    if (id <= 0 || !_box.contains(id)) return;
    _box.remove(id);
    registrarDeleteParaRede('item_lista_compra', id);
  }

  /// Volta item recebido/cancelado para pendente (correcao manual).
  ItemListaCompra reabrir(int id) {
    final item = obterPorId(id);
    if (item == null) throw StateError('Item $id nao encontrado.');
    if (item.ativo) return item;
    item.status = ListaCompraItemStatus.pendente;
    item.quantidadeRecebida = 0;
    item.resolvidoEm = null;
    item.nfeChaveResolucao = '';
    _box.put(item);
    _notificar(id);
    return item;
  }

  /// Apaga itens recebidos e/ou cancelados. [maisAntigosQueDias] opcional.
  int limparFinalizados({
    Set<String> statuses = const {
      ListaCompraItemStatus.recebido,
      ListaCompraItemStatus.cancelado,
    },
    int? maisAntigosQueDias,
  }) {
    final agora = DateTime.now().toUtc();
    final removerIds = <int>[];
    for (final item in _box.getAll()) {
      if (!statuses.contains(item.status)) continue;
      if (maisAntigosQueDias != null) {
        final ref = (item.resolvidoEm ?? item.criadoEm).toUtc();
        if (agora.difference(ref).inDays < maisAntigosQueDias) continue;
      }
      removerIds.add(item.id);
    }
    for (final id in removerIds) {
      remover(id);
    }
    return removerIds.length;
  }

  /// Conta itens que seriam removidos por [limparFinalizados].
  int contarParaLimpeza({
    Set<String> statuses = const {
      ListaCompraItemStatus.recebido,
      ListaCompraItemStatus.cancelado,
    },
    int? maisAntigosQueDias,
  }) {
    final agora = DateTime.now().toUtc();
    var n = 0;
    for (final item in _box.getAll()) {
      if (!statuses.contains(item.status)) continue;
      if (maisAntigosQueDias != null) {
        final ref = (item.resolvidoEm ?? item.criadoEm).toUtc();
        if (agora.difference(ref).inDays < maisAntigosQueDias) continue;
      }
      n++;
    }
    return n;
  }

  /// Baixa itens ativos quando mercadoria entra por NF-e (Fase 4).
  int resolverPorEntradaNfe(List<ListaCompraEntradaNfeLinha> linhas) {
    if (linhas.isEmpty) return 0;
    var itensResolvidos = 0;

    for (final entrada in linhas) {
      if (entrada.produtoId <= 0 || entrada.quantidadeRecebida <= 0) continue;

      var restante = entrada.quantidadeRecebida;
      final candidatos = listarAtivos()
          .where((i) => i.produtoId == entrada.produtoId)
          .toList()
        ..sort((a, b) {
          final pu = a.prioridade == ListaCompraItemPrioridade.urgente ? 0 : 1;
          final pub = b.prioridade == ListaCompraItemPrioridade.urgente ? 0 : 1;
          if (pu != pub) return pu.compareTo(pub);
          return a.criadoEm.compareTo(b.criadoEm);
        });

      for (final item in candidatos) {
        if (restante <= 0) break;
        final falta = item.quantidadePendenteRecebimento;
        if (falta <= 0) continue;

        final aplicar = restante < falta ? restante : falta;
        item.quantidadeRecebida += aplicar;
        restante -= aplicar;
        item.nfeChaveResolucao = entrada.nfeChave;

        if (item.quantidadeRecebida >= item.quantidadeSugerida) {
          item.status = ListaCompraItemStatus.recebido;
          item.resolvidoEm = DateTime.now().toUtc();
        } else {
          item.observacao = _anexarObservacao(
            item.observacao,
            'Recebido parcial $aplicar ${item.unidade} (NF-e)',
          );
        }
        _box.put(item);
        _notificar(item.id);
        itensResolvidos++;
      }
    }
    return itensResolvidos;
  }

  List<ListaCompraGrupoFornecedor> agruparAtivosPorFornecedor() {
    final mapa = <String, List<ItemListaCompra>>{};
    for (final item in listarAtivos()) {
      final f = item.fornecedorTexto.trim().isEmpty
          ? 'Sem fornecedor'
          : item.fornecedorTexto.trim();
      mapa.putIfAbsent(f, () => []).add(item);
    }

    final grupos = <ListaCompraGrupoFornecedor>[];
    for (final entry in mapa.entries) {
      final itens = entry.value..sort(_compararItens);
      var valor = 0.0;
      for (final item in itens) {
        final p = produtoDe(item);
        final custo = p?.precoCusto ?? 0;
        if (custo > 0) valor += custo * item.quantidadePendenteRecebimento;
      }
      grupos.add(
        ListaCompraGrupoFornecedor(
          fornecedor: entry.key,
          itens: itens,
          valorEstimado: valor,
        ),
      );
    }
    grupos.sort((a, b) => a.fornecedor.compareTo(b.fornecedor));
    return grupos;
  }

  ItemListaCompra? _buscarPendentePorProdutoId(int produtoId) {
    final q = _box
        .query(
          ItemListaCompra_.status
              .equals(ListaCompraItemStatus.pendente)
              .or(ItemListaCompra_.status.equals(ListaCompraItemStatus.cotacao))
              .or(ItemListaCompra_.status.equals(ListaCompraItemStatus.pedido)),
        )
        .build();
    try {
      for (final item in q.find()) {
        if (item.produtoId == produtoId) return item;
      }
      return null;
    } finally {
      q.close();
    }
  }

  static int _compararItens(ItemListaCompra a, ItemListaCompra b) {
    final pa = a.prioridade == ListaCompraItemPrioridade.urgente ? 0 : 1;
    final pb = b.prioridade == ListaCompraItemPrioridade.urgente ? 0 : 1;
    if (pa != pb) return pa.compareTo(pb);
    final sa = ListaCompraItemStatus.ativos.contains(a.status) ? 0 : 1;
    final sb = ListaCompraItemStatus.ativos.contains(b.status) ? 0 : 1;
    if (sa != sb) return sa.compareTo(sb);
    return b.criadoEm.compareTo(a.criadoEm);
  }

  static String _anexarObservacao(String atual, String novo) {
    final a = atual.trim();
    if (a.isEmpty) return novo;
    if (a.contains(novo)) return a;
    return '$a | $novo';
  }

  Future<Set<int>> _carregarIgnorados(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsIgnorados);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toInt()).where((id) => id > 0).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _salvarIgnorados(
    SharedPreferences prefs,
    Set<int> ids,
  ) async {
    await prefs.setString(_prefsIgnorados, jsonEncode(ids.toList()..sort()));
  }

  void _notificar(int id) {
    notificarAlteracaoParaRede(entidade: 'item_lista_compra', entidadeId: id);
  }
}

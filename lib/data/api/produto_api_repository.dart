import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/pdv_busca_inteligente.dart';
import '../../domain/produto_substitutos_util.dart';
import '../../model/historico_entrada.dart';
import '../../model/movimento_estoque.dart';
import '../../model/produto.dart';
import '../../model/produto_sugestao_venda.dart';
import '../produto_busca_util.dart';
import '../produto_repository.dart' show ProdutoSkuDuplicadoException;
import '../sync/sync_entity_codec.dart';
import '../sync/sync_entity_codec_extras.dart';
import '../sync/sync_entity_codec_operacional.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

/// Catalogo de produtos via API (cache em memoria para leituras sync na UI).
class ProdutoApiRepository extends ChangeNotifier {
  ProdutoApiRepository(this._client);

  final LanApiClient _client;
  LanApiClient get client => _client;
  final Map<int, Produto> _porId = {};
  List<Produto> _lista = [];
  bool _hidratado = false;
  int _catalogoRevision = 0;
  bool _sincronizandoCatalogo = false;
  String _productImagesCacheDir = '';

  /// Terminal leve nao tem ObjectBox; acessos devem ser evitados na UI.
  Never get objectBox => throw StateError(
        'Terminal leve: sem ObjectBox local. Use a API do PC servidor.',
      );

  /// Pasta local de cache das fotos baixadas da API (PC servidor).
  String get productImagesDirPath => _productImagesCacheDir;

  bool get hidratado => _hidratado;

  int get catalogoRevision => _catalogoRevision;

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  /// Cria/resolve pasta de cache de fotos (chamar no login do terminal).
  Future<void> garantirCacheImagens() async {
    if (_productImagesCacheDir.isNotEmpty) {
      await Directory(_productImagesCacheDir).create(recursive: true);
      return;
    }
    final base = !kIsWeb && Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'product_images_cache'));
    await dir.create(recursive: true);
    _productImagesCacheDir = dir.path;
  }

  /// Falha imediata em mutacoes/HTTP — sem fallback local.
  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  /// Baixa o catalogo completo em paginas (PDV/estoque/consulta usam este cache).
  /// Nao limitar a um unico lote — isso omitia produtos (ex.: "cimento" incompleto).
  Future<void> hidratar({String q = '', int pageSize = 500}) async {
    _exigirServidorOnline();
    final tamanho = pageSize.clamp(50, 1000);
    final todos = <Produto>[];
    final idsVistos = <int>{};
    var offset = 0;
    while (true) {
      final pagina = await _client.listarProdutos(
        q: q,
        limit: tamanho,
        offset: offset,
        somenteAtivos: false,
      );
      if (pagina.isEmpty) break;
      var novos = 0;
      for (final p in pagina) {
        if (p.id <= 0) continue;
        if (idsVistos.add(p.id)) {
          todos.add(p);
          novos++;
        }
      }
      // Servidor sem suporte a offset devolve sempre a 1a pagina — para aqui.
      if (novos == 0 || pagina.length < tamanho) break;
      offset += pagina.length;
      if (offset >= 100000) break;
    }
    _lista = todos;
    _porId
      ..clear()
      ..addEntries(todos.map((p) => MapEntry(p.id, p)));
    _hidratado = true;
    notifyListeners();
  }

  /// Atualiza o cache apos evento WS: ids pontuais ou catalogo completo.
  Future<void> aplicarEventoRede({
    List<int> ids = const [],
    int? revision,
  }) async {
    if (_offline) return;
    if (ids.isNotEmpty) {
      await atualizarEstoquePorIds(ids);
      if (revision != null && revision > _catalogoRevision) {
        _catalogoRevision = revision;
      }
      return;
    }
    await hidratar();
    if (revision != null && revision > _catalogoRevision) {
      _catalogoRevision = revision;
    } else {
      await _puxarRevisionSilencioso();
    }
  }

  /// Fallback: se a revisao do servidor mudou, reidrata o catalogo.
  /// Retorna true se houve atualizacao.
  Future<bool> sincronizarSeDesatualizado({bool forcar = false}) async {
    if (_offline || _sincronizandoCatalogo) return false;
    _sincronizandoCatalogo = true;
    try {
      if (forcar || !_hidratado) {
        await hidratar();
        await _puxarRevisionSilencioso();
        return true;
      }
      final meta = await _client.obterCatalogoProdutoMeta();
      final remota = (meta['revision'] as num?)?.toInt() ?? 0;
      final countRemoto = (meta['count'] as num?)?.toInt() ?? -1;
      if (remota > _catalogoRevision ||
          (countRemoto >= 0 && countRemoto != _lista.length)) {
        await hidratar();
        _catalogoRevision = remota > _catalogoRevision ? remota : _catalogoRevision;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _sincronizandoCatalogo = false;
    }
  }

  Future<void> _puxarRevisionSilencioso() async {
    try {
      final meta = await _client.obterCatalogoProdutoMeta();
      final remota = (meta['revision'] as num?)?.toInt() ?? 0;
      if (remota > _catalogoRevision) _catalogoRevision = remota;
    } catch (_) {}
  }

  /// Atualiza so os produtos afetados (evento WS com ids) — bem mais rapido que [hidratar].
  Future<void> atualizarEstoquePorIds(List<int> ids) async {
    if (ids.isEmpty) return;
    _exigirServidorOnline();
    final atualizados = <Produto>[];
    for (final id in ids.toSet()) {
      if (id <= 0) continue;
      final p = await _client.obterProduto(id);
      if (p != null) atualizados.add(p);
    }
    if (atualizados.isEmpty) return;
    _mesclarNoCache(atualizados);
  }

  /// Libera cache pesado (logout / standby do terminal).
  void limparCache() {
    _lista = [];
    _porId.clear();
    _hidratado = false;
    _catalogoRevision = 0;
    notifyListeners();
  }

  void _mesclarNoCache(Iterable<Produto> items) {
    var mudou = false;
    for (final p in items) {
      if (p.id <= 0) continue;
      final anterior = _porId[p.id];
      _porId[p.id] = p;
      if (anterior == null) {
        _lista.add(p);
        mudou = true;
      } else {
        final i = _lista.indexWhere((x) => x.id == p.id);
        if (i >= 0) {
          _lista[i] = p;
          mudou = true;
        } else {
          _lista.add(p);
          mudou = true;
        }
      }
    }
    if (mudou) notifyListeners();
  }

  /// Busca paginada direto na API e mescla no cache (cadastro / fallback).
  Future<List<Produto>> pesquisarRemoto(
    String termo, {
    int offset = 0,
    int limite = 40,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) async {
    _exigirServidorOnline();
    final items = await _client.listarProdutos(
      q: termo,
      limit: limite,
      offset: offset,
      somenteAtivos: somenteAtivos && !somenteInativos,
      somenteInativos: somenteInativos,
    );
    _mesclarNoCache(items);
    return items;
  }

  Produto? obterPorId(int id) => _porId[id];

  /// Substitutos cadastrados no produto (mesma regra do ObjectBox).
  List<Produto> listarSubstitutosCadastrados(int produtoId) {
    if (produtoId <= 0 || _offline) return const [];
    final ref = obterPorId(produtoId);
    if (ref == null) return const [];
    final ids = ProdutoSubstitutosUtil.parseIds(ref.substitutosIds);
    if (ids.isEmpty) return const [];
    final out = <Produto>[];
    for (final id in ids) {
      if (id == produtoId) continue;
      final p = obterPorId(id);
      if (p == null || !p.ativo) continue;
      out.add(p);
    }
    return out;
  }

  List<Produto> listarTodos({bool somenteAtivos = false}) {
    if (_offline) return const [];
    var base = List<Produto>.from(_lista);
    if (somenteAtivos) {
      base = base.where((p) => p.ativo).toList();
    }
    return List.unmodifiable(base);
  }

  List<Produto> listarPaginado({
    int offset = 0,
    int limit = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    String? prefixoNome,
  }) {
    if (_offline) return const [];
    var base = List<Produto>.from(_lista);
    if (somenteInativos) {
      base = base.where((p) => !p.ativo).toList();
    } else if (somenteAtivos) {
      base = base.where((p) => p.ativo).toList();
    }
    final pfx = (prefixoNome ?? '').trim().toLowerCase();
    if (pfx.isNotEmpty) {
      base = base
          .where((p) => p.nome.trim().toLowerCase().startsWith(pfx))
          .toList();
    }
    base.sort(
      (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
    );
    if (offset >= base.length) return const [];
    final end = (offset + limit).clamp(0, base.length);
    return base.sublist(offset, end);
  }

  List<Produto> pesquisar(
    String termo, {
    int? clienteId,
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    bool excluirProdutosInternos = false,
  }) {
    if (_offline) return const [];
    // Mesmo contrato do ObjectBox: curingas `%`, acentos, ranking basico.
    // [clienteId] reservado para paridade de assinatura (historico no PC1).
    return pesquisarProdutosEmMemoria(
      _lista,
      termo,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: excluirProdutosInternos,
    );
  }

  List<Produto> pesquisarPadraoPdv(
    String termo, {
    int? clienteId,
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) {
    return pesquisar(
      termo,
      clienteId: clienteId,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    );
  }

  /// Pagina de busca para o dialogo de cadastro (mesmo contrato do ObjectBox).
  Future<List<Produto>> pesquisarPaginaCadastro(
    String termo, {
    int offset = 0,
    int limite = 40,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) async {
    final t = termo.trim();
    if (t.isNotEmpty) {
      return pesquisarRemoto(
        t,
        offset: offset,
        limite: limite,
        somenteAtivos: somenteAtivos,
        somenteInativos: somenteInativos,
      );
    }
    // Sem texto: pagina o cache (mais rapido). Se vazio, hidrata e tenta remoto.
    final local = pesquisarPadraoPdv(
      termo,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
    );
    if (local.isNotEmpty || _offline) return local;
    if (!_hidratado) {
      await hidratar();
      return pesquisarPadraoPdv(
        termo,
        offset: offset,
        limite: limite,
        somenteAtivos: somenteAtivos,
        somenteInativos: somenteInativos,
      );
    }
    return pesquisarRemoto(
      '',
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
    );
  }

  List<Produto> pesquisarNaBasePadraoPdv(
    String termo,
    Iterable<Produto> base, {
    int limite = 500,
    bool somenteAtivos = false,
    bool somenteInativos = false,
  }) {
    final listaBase = base is List<Produto> ? base : base.toList();
    final t = termo.trim();
    if (t.isEmpty) return listaBase;
    final idsBase = listaBase.map((p) => p.id).toSet();
    return pesquisar(
      t,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    ).where((p) => idsBase.contains(p.id)).toList();
  }

  Produto? buscarPorCodigoBarras(
    String codigo, {
    bool somenteAtivos = true,
  }) {
    return resolverLeitorCodigoBarras(codigo, somenteAtivos: somenteAtivos);
  }

  Produto? resolverLeitorCodigoBarras(
    String termo, {
    bool somenteAtivos = true,
  }) {
    if (_offline) return null;
    final t = termo.trim();
    if (t.isEmpty) return null;
    final dig = normalizarCodigoBarrasConsulta(t);
    for (final p in _lista) {
      if (somenteAtivos && !p.ativo) continue;
      if (p.codigoInterno == t) return p;
      if (dig.isNotEmpty) {
        final barras = normalizarCodigoBarrasConsulta(p.codigoBarras);
        if (barras == dig) return p;
        final alts = codigosBarrasAlternativosDeApelidos(
          parseApelidosBusca(p.apelidosBusca),
        );
        if (alts.contains(dig)) return p;
      } else if (p.codigoBarras == t) {
        return p;
      }
    }
    return null;
  }

  PdvPesquisaResolvida resolverPesquisaPdv(
    String termo, {
    int? clienteId,
    bool somenteAtivos = true,
  }) {
    final consulta = termo.trim();
    if (consulta.isEmpty) return PdvPesquisaResolvida.vazia;
    final barras = resolverLeitorCodigoBarras(
      consulta,
      somenteAtivos: somenteAtivos,
    );
    if (barras != null) {
      return PdvPesquisaResolvida(
        produtos: [barras],
        totalCorrespondencias: 1,
        produtoAuto: barras,
        motivoAuto: PdvBuscaAutoMotivo.codigoBarras,
      );
    }
    final lista = pesquisarPadraoPdv(
      consulta,
      clienteId: clienteId,
      limite: 40,
      somenteAtivos: somenteAtivos,
    );
    if (lista.length == 1) {
      return PdvPesquisaResolvida(
        produtos: lista,
        totalCorrespondencias: 1,
        produtoAuto: lista.first,
        motivoAuto: PdvBuscaAutoMotivo.unicoResultado,
      );
    }
    return PdvPesquisaResolvida(
      produtos: lista,
      totalCorrespondencias: lista.length,
    );
  }

  void atualizarCacheAposMovimentoEstoque() {}

  void invalidarCacheBusca() {
    notifyListeners();
  }

  String proximoSkuAutomatico({int? ignorarProdutoId}) {
    final codigos = <String>[];
    for (final p in listarTodos()) {
      if (ignorarProdutoId != null && p.id == ignorarProdutoId) continue;
      codigos.add(p.codigoInterno);
    }
    var sku = proximoSkuNumericoSequencial(codigos);
    var tentativas = 0;
    while (obterPorCodigoInterno(sku, ignorarProdutoId: ignorarProdutoId) !=
            null &&
        tentativas < 1000) {
      final n = int.tryParse(sku) ?? 0;
      sku = '${n + 1}';
      tentativas++;
    }
    return sku;
  }

  /// Proximo SKU autoritativo no PC1 (evita corrida entre terminais).
  Future<String> proximoSkuAutomaticoRemoto({int? ignorarProdutoId}) async {
    _exigirServidorOnline();
    final sku = await _client.proximoSkuProduto(
      ignorarProdutoId: ignorarProdutoId,
    );
    if (sku.trim().isNotEmpty) return sku.trim();
    return proximoSkuAutomatico(ignorarProdutoId: ignorarProdutoId);
  }

  Future<Produto?> obterPorIdRemoto(int id) async {
    if (id <= 0) return null;
    _exigirServidorOnline();
    final p = await _client.obterProduto(id);
    if (p != null) _mesclarNoCache([p]);
    return p;
  }

  Produto? obterPorCodigoInterno(String codigo, {int? ignorarProdutoId}) {
    final lista = listarPorCodigoInterno(
      codigo,
      ignorarProdutoId: ignorarProdutoId,
    );
    return lista.isEmpty ? null : lista.first;
  }

  List<Produto> listarPorCodigoInterno(
    String codigo, {
    int? ignorarProdutoId,
  }) {
    if (_offline) return const [];
    final c = codigo.trim();
    if (c.isEmpty) return const [];
    return _lista
        .where((p) {
          if (ignorarProdutoId != null && p.id == ignorarProdutoId) {
            return false;
          }
          return skuBuscaCorrespondeExato(c, p.codigoInterno);
        })
        .toList();
  }

  /// Busca EAN/SKU no servidor quando o cache local nao acha (cadastro/leitor).
  Future<Produto?> buscarPorCodigoBarrasRemoto(
    String codigo, {
    bool somenteAtivos = true,
  }) async {
    final local = resolverLeitorCodigoBarras(
      codigo,
      somenteAtivos: somenteAtivos,
    );
    if (local != null) return local;
    if (_offline) return null;
    final t = codigo.trim();
    if (t.isEmpty) return null;
    try {
      final remotos = await pesquisarRemoto(
        t,
        limite: 20,
        somenteAtivos: somenteAtivos,
        somenteInativos: !somenteAtivos,
      );
      for (final p in remotos) {
        if (somenteAtivos && !p.ativo) continue;
        if (skuBuscaCorrespondeExato(t, p.codigoInterno)) return p;
        final dig = normalizarCodigoBarrasConsulta(t);
        if (dig.isNotEmpty &&
            normalizarCodigoBarrasConsulta(p.codigoBarras) == dig) {
          return p;
        }
      }
    } catch (_) {}
    return null;
  }

  DateTime? obterDataUltimaCompraProduto(int produtoId) {
    // Sync stub — use [obterDataUltimaCompraProdutoRemoto] no cadastro.
    return null;
  }

  Future<DateTime?> obterDataUltimaCompraProdutoRemoto(int produtoId) async {
    if (produtoId <= 0) return null;
    final hist = await listarHistoricoEntradaPorProdutoRemoto(produtoId);
    if (hist.isEmpty) return null;
    hist.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
    return hist.first.dataEmissao;
  }

  int contarProdutosComFotoPath(
    String path, {
    int? excluirProdutoId,
  }) {
    final alvo = path.trim();
    if (alvo.isEmpty) return 0;
    var n = 0;
    for (final p in _lista) {
      if (excluirProdutoId != null && p.id == excluirProdutoId) continue;
      if (p.fotoPath.trim() == alvo) n++;
    }
    return n;
  }

  ({int alterados, int inalterados}) padronizarNomesTituloEmLote() =>
      (alterados: 0, inalterados: 0);

  double? calcularCustoMedioPonderadoPorEntradasNfe(int produtoId) => null;

  Future<double?> calcularCustoMedioPonderadoPorEntradasNfeRemoto(
    int produtoId,
  ) async {
    if (produtoId <= 0) return null;
    final hist = await listarHistoricoEntradaPorProdutoRemoto(produtoId);
    var somaValor = 0.0;
    var somaQtd = 0;
    for (final h in hist) {
      final qtd = h.quantidadeEntradaEstoque;
      final unit = h.precoCustoUnitarioNota;
      if (qtd <= 0 || unit <= 0) continue;
      somaValor += qtd * unit;
      somaQtd += qtd;
    }
    if (somaQtd <= 0) return null;
    return somaValor / somaQtd;
  }

  Future<List<ProdutoSugestaoVenda>> listarSugestoesVendaRemoto(
    int produtoOrigemId, {
    bool somenteAtivas = true,
  }) async {
    if (produtoOrigemId <= 0) return const [];
    _exigirServidorOnline();
    final raw = await _client.listarSugestoesVendaProduto(produtoOrigemId);
    final lista = raw
        .map(SyncEntityCodecOperacional.produtoSugestaoVendaDeMap)
        .toList();
    if (!somenteAtivas) return lista;
    return lista.where((s) => s.ativo).toList();
  }

  Future<void> substituirSugestoesVendaRemoto(
    int produtoOrigemId,
    List<ProdutoSugestaoVenda> sugestoes,
  ) async {
    if (produtoOrigemId <= 0) return;
    _exigirServidorOnline();
    await _client.salvarSugestoesVendaProduto(
      produtoOrigemId,
      sugestoes
          .map(SyncEntityCodecOperacional.produtoSugestaoVendaParaMap)
          .toList(),
    );
  }

  Future<int> removerVarios(Iterable<int> ids) async {
    var n = 0;
    for (final id in ids.toSet()) {
      if (id <= 0) continue;
      if (await removerRemoto(id)) n++;
    }
    return n;
  }

  Future<int> aplicarFotoEmVarios({
    required Iterable<int> ids,
    required String fotoPath,
  }) async {
    final path = fotoPath.trim();
    if (path.isEmpty) return 0;
    // Basename sincronizado no servidor; bytes sobem via upload antes.
    final basename = p.basename(path);
    var n = 0;
    for (final id in ids.toSet()) {
      if (id <= 0) continue;
      final prod = obterPorId(id) ?? await obterPorIdRemoto(id);
      if (prod == null) continue;
      if (prod.fotoPath.trim() == path || prod.fotoPath.trim() == basename) {
        continue;
      }
      prod.fotoPath = basename.isNotEmpty ? basename : path;
      await salvarRemoto(prod);
      n++;
    }
    return n;
  }

  Future<int> salvarRemoto(Produto produto) async {
    _exigirServidorOnline();
    try {
      final id = await _client.salvarProduto(produto);
      if (id > 0) {
        produto.id = id;
        _mesclarNoCache([produto]);
        final fresco = await _client.obterProduto(id);
        if (fresco != null) _mesclarNoCache([fresco]);
      } else {
        await hidratar();
      }
      return id;
    } on LanApiException catch (e) {
      if (e.code == 'sku_duplicado') {
        final d = e.details;
        throw ProdutoSkuDuplicadoException(
          sku: (d?['sku'] ?? produto.codigoInterno).toString(),
          produtoExistenteNome:
              (d?['produtoExistenteNome'] ?? '').toString(),
          produtoExistenteId: (d?['produtoExistenteId'] as num?)?.toInt(),
        );
      }
      rethrow;
    }
  }

  void sincronizarCustoMedioInteligenteParaProduto(
    int produtoId, {
    bool forcar = false,
  }) {}

  void sincronizarCustoMedioInteligenteParaProdutos(
    Iterable<int> ids, {
    bool forcar = false,
  }) {}

  Future<void> ajustarEstoqueManualRemoto({
    required int produtoId,
    required int novaQuantidadeFisica,
    required String motivo,
    String usuarioLogin = '',
    String usuarioId = '',
    String numeroLote = '',
    DateTime? dataValidade,
  }) async {
    _exigirServidorOnline();
    final m = await _client.ajustarEstoque(
      produtoId: produtoId,
      quantidadeAjustada: novaQuantidadeFisica,
      motivo: motivo,
      usuarioLogin: usuarioLogin,
      usuarioId: usuarioId.isNotEmpty ? usuarioId : usuarioLogin,
      numeroLote: numeroLote,
      dataValidade: dataValidade,
    );
    final item = m['item'];
    if (item is Map) {
      _mesclarNoCache([
        SyncEntityCodec.produtoDeMap(Map<String, dynamic>.from(item)),
      ]);
      return;
    }
    await atualizarEstoquePorIds([produtoId]);
  }

  void ajustarEstoqueManual({
    required int produtoId,
    required int novaQuantidadeFisica,
    required String motivo,
    String usuarioLogin = '',
  }) {
    throw StateError(
      'Terminal leve: use ajustarEstoqueManualRemoto (async) no estoque.',
    );
  }

  bool remover(int id) {
    throw StateError(
      'Terminal leve: use removerRemoto (async) no cadastro de produtos.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerProduto(id);
    if (ok) {
      _porId.remove(id);
      _lista.removeWhere((p) => p.id == id);
      notifyListeners();
    }
    return ok;
  }

  int salvar(Produto produto) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  Future<List<MovimentoEstoque>> listarMovimentosEstoquePorProduto(
    int produtoId, {
    int limite = 200,
  }) async {
    _exigirServidorOnline();
    final raw = await _client.listarMovimentosEstoque(
      produtoId: produtoId,
      limit: limite,
    );
    return raw
        .map(SyncEntityCodecOperacional.movimentoEstoqueDeMap)
        .toList(growable: false);
  }

  Future<List<HistoricoEntrada>> listarHistoricoEntradaPorProdutoRemoto(
    int produtoId, {
    int limite = 100,
  }) async {
    _exigirServidorOnline();
    final raw = await _client.listarHistoricoEntradaProduto(
      produtoId,
      limit: limite,
    );
    return raw
        .map(SyncEntityCodecExtras.historicoEntradaDeMap)
        .toList(growable: false);
  }

  /// Sync stub: use [listarHistoricoEntradaPorProdutoRemoto] no terminal.
  List<HistoricoEntrada> listarHistoricoEntradaPorProduto(int produtoId) =>
      const [];

  Future<void> consolidarFotosDuplicadas() async {}
}

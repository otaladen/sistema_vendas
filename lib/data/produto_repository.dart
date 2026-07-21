import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/historico_entrada.dart';
import '../model/item_lista_compra.dart';
import '../model/item_venda.dart';
import '../model/movimento_estoque.dart';
import '../model/produto.dart';
import '../model/vinculo_fornecedor_produto.dart';
import '../domain/produto_imagem_nome_arquivo.dart';
import '../domain/pdv_consulta_similares_util.dart';
import '../domain/produto_substitutos_util.dart';
import '../domain/pdv_busca_inteligente.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/produto_nome_titulo_normalizer.dart';
import '../services/gerenciador_estoque_service.dart';
import '../services/produto_imagem_service.dart';
import 'movimento_estoque_repository.dart';
import 'produto_busca_sinonimos.dart';
import 'produto_busca_util.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_delete_outbox.dart';
import 'sync/sync_dirty_outbox.dart';
import 'sync/sync_write_trigger.dart';

/// Resultado de [ProdutoRepository.zerarCadastroCompleto].
class ProdutoCadastroZerarResultado {
  const ProdutoCadastroZerarResultado({
    required this.produtosRemovidos,
    required this.movimentosRemovidos,
    required this.historicosEntradaRemovidos,
    required this.vinculosRemovidos,
    required this.kitsRemovidos,
    required this.kitItensRemovidos,
    required this.promocoesRemovidas,
    required this.promocaoItensRemovidos,
    required this.promocaoCombosRemovidos,
    required this.sugestoesRemovidas,
    required this.metricasSugestaoRemovidas,
    required this.itensListaCompraRemovidos,
    required this.imagensRemovidas,
  });

  final int produtosRemovidos;
  final int movimentosRemovidos;
  final int historicosEntradaRemovidos;
  final int vinculosRemovidos;
  final int kitsRemovidos;
  final int kitItensRemovidos;
  final int promocoesRemovidas;
  final int promocaoItensRemovidos;
  final int promocaoCombosRemovidos;
  final int sugestoesRemovidas;
  final int metricasSugestaoRemovidas;
  final int itensListaCompraRemovidos;
  final int imagensRemovidas;
}

/// Media ponderada (quantidade interna * custo unitario da nota) sobre todas as
/// [HistoricoEntrada] do produto. Retorna null se nao houver linhas validas.
double? calcularCustoMedioPonderadoEntradasNfe(ObjectBox db, int produtoId) {
  if (produtoId <= 0) return null;
  final q = db.historicoEntradaBox
      .query(HistoricoEntrada_.produto.equals(produtoId))
      .build();
  try {
    var somaValor = 0.0;
    var somaQtd = 0;
    for (final h in q.find()) {
      final qtd = h.quantidadeEntradaEstoque;
      final unit = h.precoCustoUnitarioNota;
      if (qtd <= 0 || unit <= 0) continue;
      somaValor += qtd * unit;
      somaQtd += qtd;
    }
    if (somaQtd <= 0) return null;
    return somaValor / somaQtd;
  } finally {
    q.close();
  }
}

/// Lancada ao gravar produto com SKU ja usado por outro cadastro.
class ProdutoSkuDuplicadoException implements Exception {
  ProdutoSkuDuplicadoException({
    required this.sku,
    required this.produtoExistenteNome,
    this.produtoExistenteId,
  });

  final String sku;
  final String produtoExistenteNome;
  final int? produtoExistenteId;

  @override
  String toString() =>
      'SKU "$sku" ja cadastrado no produto "$produtoExistenteNome".';
}

class ProdutoRepository extends ChangeNotifier {
  ProdutoRepository(this._db) : _estoque = GerenciadorEstoqueService(_db);

  final ObjectBox _db;
  final GerenciadorEstoqueService _estoque;

  ObjectBox get objectBox => _db;

  static const List<String> _unidadesValidas = [
    'UN',
    'M',
    'M2',
    'M3',
    'KG',
    'SC',
    'CX',
    'LT',
  ];
  static const Duration _cacheTtl = Duration(minutes: 2);

  List<_ProdutoBuscaDoc> _cacheDocs = const [];
  int _cacheProdutoCount = -1;
  int _cacheItemCount = -1;
  int _cacheVendaCount = -1;
  DateTime? _cacheMontadoEm;
  Map<int, double> _cacheScoreHistorico = const {};
  final Map<int, Map<int, double>> _cacheScoreCliente = {};

  /// >0: [salvar]/invalidacao nao notifica UI/rede (importacao em lote).
  int _importacaoEmLoteDepth = 0;

  static bool _migracaoAtivoLegadoOk = false;

  String get productImagesDirPath => _db.productImagesDir.path;

  /// Quando [somenteAtivos] e true, retorna apenas produtos vendiveis (PDV).
  /// Padrao false: cadastro, estoque, relatorios e resolucao de itens antigos em orcamentos.
  List<Produto> listarTodos({bool somenteAtivos = false}) {
    _migrarCampoAtivoLegadoUmaVez();
    late final List<Produto> produtos;
    if (somenteAtivos) {
      final query = _db.produtoBox
          .query(Produto_.ativo.equals(true))
          .order(Produto_.nome)
          .build();
      try {
        produtos = query.find();
      } finally {
        query.close();
      }
    } else {
      final query = _db.produtoBox.query().order(Produto_.nome).build();
      try {
        produtos = query.find();
      } finally {
        query.close();
      }
    }
    _normalizarDadosLegados(produtos);
    return produtos;
  }

  /// Pagina produtos ordenados por nome (sugestoes PDV sem carregar catalogo inteiro).
  List<Produto> listarPaginado({
    int offset = 0,
    int limit = 50,
    bool somenteAtivos = true,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    if (limit <= 0) return const [];
    final qb = somenteAtivos
        ? _db.produtoBox.query(Produto_.ativo.equals(true))
        : _db.produtoBox.query();
    final query = qb.order(Produto_.nome).build();
    try {
      query.offset = offset < 0 ? 0 : offset;
      query.limit = limit;
      final produtos = query.find();
      _normalizarDadosLegados(produtos);
      return produtos;
    } finally {
      query.close();
    }
  }

  /// Candidatos para sugestao de substitutos na consulta PDV.
  List<Produto> listarCandidatosSimilaresConsulta(
    Produto referencia, {
    int limite = 80,
  }) {
    if (referencia.id <= 0 || limite <= 0) return const [];
    if (!PdvConsultaSimilaresUtil.referenciaElegivel(referencia)) {
      return const [];
    }
    _migrarCampoAtivoLegadoUmaVez();

    final categoria = referencia.categoria.trim();
    final subcategoria = referencia.subcategoria.trim();
    late final Query<Produto> query;

    if (PdvConsultaSimilaresUtil.subcategoriaUtil(subcategoria)) {
      query = _db.produtoBox
          .query(
            Produto_.ativo.equals(true) &
                Produto_.subcategoria.equals(subcategoria, caseSensitive: false),
          )
          .order(Produto_.nome)
          .build();
    } else if (PdvConsultaSimilaresUtil.categoriaEspecifica(categoria)) {
      query = _db.produtoBox
          .query(
            Produto_.ativo.equals(true) &
                Produto_.categoria.equals(categoria, caseSensitive: false),
          )
          .order(Produto_.nome)
          .build();
    } else {
      return const [];
    }

    try {
      query.limit = limite + 1;
      final produtos = query
          .find()
          .where(
            (p) =>
                p.id != referencia.id &&
                PdvConsultaSimilaresUtil.candidatoCompativel(referencia, p),
          )
          .take(limite)
          .toList();
      _normalizarDadosLegados(produtos);
      return produtos;
    } finally {
      query.close();
    }
  }

  /// Substitutos cadastrados manualmente no produto (consulta PDV pacote 5).
  List<Produto> listarSubstitutosCadastrados(int produtoId) {
    if (produtoId <= 0) return const [];
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

  /// Migracao unica: registros antigos ganham coluna [ativo]; define todos como ativos.
  void _migrarCampoAtivoLegadoUmaVez() {
    if (_migracaoAtivoLegadoOk) return;
    try {
      final flag = File(
        p.join(_db.storeDirectoryPath, '.migracao_produto_ativo_v1'),
      );
      if (flag.existsSync()) {
        _migracaoAtivoLegadoOk = true;
        return;
      }
      _db.store.runInTransaction(TxMode.write, () {
        final todos = _db.produtoBox.getAll();
        for (final prod in todos) {
          prod.ativo = true;
          _db.produtoBox.put(prod);
        }
      });
      flag.writeAsStringSync('ok');
      _invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      _migracaoAtivoLegadoOk = true;
    } catch (_) {
      // Falha de IO: proxima chamada tenta novamente.
    }
  }

  void _normalizarDadosLegados(List<Produto> produtos) {
    final alterados = <Produto>[];
    for (final produto in produtos) {
      final unidade = produto.unidade.trim();
      final unidadeValida = _unidadesValidas.contains(unidade);
      var houveAjuste = false;
      if (!unidadeValida) {
        produto.unidade = 'UN';
        houveAjuste = true;
      }
      final precoBase = produto.precoVenda > 0 ? produto.precoVenda : 0.0;
      if (produto.preco1 <= 0 && precoBase > 0) {
        produto.preco1 = precoBase;
        houveAjuste = true;
      }
      if (produto.preco2 <= 0 && precoBase > 0) {
        produto.preco2 = precoBase;
        houveAjuste = true;
      }
      if (produto.preco3 <= 0 && precoBase > 0) {
        produto.preco3 = precoBase;
        houveAjuste = true;
      }
      if (produto.estoqueAtual != produto.estoqueReal) {
        produto.estoqueAtual = produto.estoqueReal;
        houveAjuste = true;
      }
      if (produto.leadTimeDias <= 0) {
        produto.leadTimeDias = 7;
        houveAjuste = true;
      }
      if (produto.estoqueSeguranca <= 0 && produto.quantidadeMinima > 0) {
        produto.estoqueSeguranca = produto.quantidadeMinima;
        houveAjuste = true;
      }
      if (houveAjuste) {
        alterados.add(produto);
      }
    }
    if (alterados.isEmpty) {
      return;
    }
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in alterados) {
        _db.produtoBox.put(p);
      }
    });
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
  }

  /// - [somenteAtivos] padrao true (PDV): ignora inativos.
  /// - [somenteInativos]: quando true, retorna apenas inativos ([somenteAtivos] e ignorado).
  /// - Ambos false: todos os produtos (cadastro / busca ampla).
  List<Produto> pesquisar(
    String termo, {
    int? clienteId,
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    bool excluirProdutosInternos = false,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    _garantirCachesAtualizados();
    final consultaBruta = termo.trim();

    if (consultaBruta.contains('%')) {
      final consultaCuringa = normalizarConsultaCuringa(
        consultaBruta,
        _normalizarTexto,
      );
      if (consultaUsaModoCuringa(consultaCuringa)) {
        final curinga = parseConsultaCuringa(consultaCuringa);
        if (curinga == null) return const [];
        return _pesquisarModoCuringa(
          segmentos: curinga.segmentos,
          clienteId: clienteId,
          offset: offset,
          limite: limite,
          somenteAtivos: somenteAtivos,
          somenteInativos: somenteInativos,
          excluirProdutosInternos: excluirProdutosInternos,
        );
      }
    }

    final consultaNormalizada = _normalizarTexto(consultaBruta);
    final parseObra = tokenizarConsultaObra(consultaNormalizada);
    final tokensSignificativos = parseObra.tokensSignificativos;
    final tokensExpandidos = {
      ...tokensSignificativos,
      ...expandirTokensBuscaComSinonimos(tokensSignificativos),
      ...expandirTokensMedidasObra(tokensSignificativos),
    }.toList();
    if (consultaNormalizada.isEmpty) {
      final ordenados = [..._cacheDocs]
        ..sort((a, b) => a.nomeNormalizado.compareTo(b.nomeNormalizado));
      final docs = ordenados.where(
        (d) => _incluirDocNaPesquisa(
          d,
          somenteAtivos: somenteAtivos,
          somenteInativos: somenteInativos,
          excluirProdutosInternos: excluirProdutosInternos,
        ),
      );
      return docs.map((d) => d.produto).skip(offset).take(limite).toList();
    }

    final scorePorProduto = <int, double>{};
    final scoreCliente = clienteId == null
        ? const <int, double>{}
        : _pontuacaoPorCliente(clienteId);

    for (final doc in _cacheDocs) {
      if (!_incluirDocNaPesquisa(
        doc,
        somenteAtivos: somenteAtivos,
        somenteInativos: somenteInativos,
        excluirProdutosInternos: excluirProdutosInternos,
      )) {
        continue;
      }
      final score = _scoreProduto(
        doc,
        consultaNormalizada: consultaNormalizada,
        consultaCompacta: parseObra.consultaCompacta,
        frasesConsulta: parseObra.frases,
        tokensSignificativos: tokensSignificativos,
        tokensExpandidos: tokensExpandidos,
        palavrasObrigatorias: palavrasObrigatoriasConsultaObra(
          tokensSignificativos,
        ),
        scoreHistoricoVenda: _cacheScoreHistorico[doc.produto.id] ?? 0,
        scoreCliente: scoreCliente[doc.produto.id] ?? 0,
      );
      if (score > 0) {
        scorePorProduto[doc.produto.id] = score;
      }
    }

    final resultados =
        _cacheDocs
            .where((d) => scorePorProduto.containsKey(d.produto.id))
            .toList()
          ..sort((a, b) {
            final scoreA = scorePorProduto[a.produto.id] ?? 0;
            final scoreB = scorePorProduto[b.produto.id] ?? 0;
            final byScore = scoreB.compareTo(scoreA);
            if (byScore != 0) return byScore;
            return a.nomeNormalizado.compareTo(b.nomeNormalizado);
          });

    return resultados.map((d) => d.produto).skip(offset).take(limite).toList();
  }

  /// Pagina de busca para listas longas (cadastro, estoque).
  List<Produto> pesquisarPaginaCadastro(
    String termo, {
    int offset = 0,
    int limite = 40,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) {
    return pesquisarPadraoPdv(
      termo,
      offset: offset,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
    );
  }

  bool _incluirDocNaPesquisa(
    _ProdutoBuscaDoc doc, {
    required bool somenteAtivos,
    required bool somenteInativos,
    required bool excluirProdutosInternos,
  }) {
    if (excluirProdutosInternos &&
        produtoEhCadastroInternoSistema(doc.produto)) {
      return false;
    }
    if (somenteInativos) return !doc.produto.ativo;
    if (somenteAtivos) return doc.produto.ativo;
    return true;
  }

  List<Produto> _pesquisarModoCuringa({
    required List<String> segmentos,
    int? clienteId,
    int offset = 0,
    required int limite,
    required bool somenteAtivos,
    required bool somenteInativos,
    required bool excluirProdutosInternos,
  }) {
    final scorePorProduto = <int, double>{};
    final scoreCliente = clienteId == null
        ? const <int, double>{}
        : _pontuacaoPorCliente(clienteId);

    for (final doc in _cacheDocs) {
      if (!_incluirDocNaPesquisa(
        doc,
        somenteAtivos: somenteAtivos,
        somenteInativos: somenteInativos,
        excluirProdutosInternos: excluirProdutosInternos,
      )) {
        continue;
      }
      final score = _scoreProdutoCuringa(
        doc,
        segmentos: segmentos,
        scoreHistoricoVenda: _cacheScoreHistorico[doc.produto.id] ?? 0,
        scoreCliente: scoreCliente[doc.produto.id] ?? 0,
      );
      if (score > 0) {
        scorePorProduto[doc.produto.id] = score;
      }
    }

    final resultados =
        _cacheDocs
            .where((d) => scorePorProduto.containsKey(d.produto.id))
            .toList()
          ..sort((a, b) {
            final scoreA = scorePorProduto[a.produto.id] ?? 0;
            final scoreB = scorePorProduto[b.produto.id] ?? 0;
            final byScore = scoreB.compareTo(scoreA);
            if (byScore != 0) return byScore;
            return a.nomeNormalizado.compareTo(b.nomeNormalizado);
          });

    return resultados.map((d) => d.produto).skip(offset).take(limite).toList();
  }

  double _scoreProdutoCuringa(
    _ProdutoBuscaDoc doc, {
    required List<String> segmentos,
    required double scoreHistoricoVenda,
    required double scoreCliente,
  }) {
    final nome = doc.nomeNormalizado;
    var match = avaliarMatchCuringa(nome, segmentos);
    var todosNoNome = match != null;

    if (match == null) {
      final texto = textoBuscaCuringaProduto(
        nomeNormalizado: nome,
        apelidosNormalizados: doc.apelidosNormalizados,
      );
      match = avaliarMatchCuringa(texto, segmentos);
      if (match == null) return 0;
      todosNoNome = false;
    }

    var score = 920.0;
    score += segmentos.length * 200;
    score += math.max(0, 380 - match.totalSpan);
    score += math.max(0, 50 - nome.length * 0.12);
    if (todosNoNome) {
      score += 300;
    } else {
      score -= 80;
    }

    if (doc.produto.estoqueReal > 0) {
      score += math.min(35, doc.produto.estoqueReal.toDouble());
    } else {
      score -= 60;
    }

    score += scoreHistoricoVenda * 0.4;
    score += scoreCliente * 0.4;

    return score;
  }

  /// Resolucao exata por GTIN (campo [Produto.codigoBarras] ou digitos em [apelidosBusca]).
  Produto? buscarPorCodigoBarras(
    String codigo, {
    bool somenteAtivos = true,
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    final dig = normalizarCodigoBarrasConsulta(codigo);
    if (dig.isEmpty) return null;
    _garantirCachesAtualizados();
    for (final doc in _cacheDocs) {
      if (!doc.correspondeCodigoBarras(dig)) continue;
      if (somenteAtivos && !doc.produto.ativo) return null;
      return doc.produto;
    }
    final q = _db.produtoBox
        .query(Produto_.codigoBarras.equals(dig))
        .build();
    try {
      final lista = q.find();
      for (final p in lista) {
        if (somenteAtivos && !p.ativo) continue;
        return p;
      }
    } finally {
      q.close();
    }
    return null;
  }

  /// Motor de busca do PDV: ranking, curingas `%`, apelidos, EAN; sem produtos `__...__`.
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

  /// Busca PDV com regra de auto-selecao: so quando ha exatamente 1 correspondencia
  /// real (codigo de barras, codigo interno ou unico no ranking).
  PdvPesquisaResolvida resolverPesquisaPdv(
    String termo, {
    int? clienteId,
    bool somenteAtivos = true,
  }) {
    final consulta = termo.trim();
    if (consulta.isEmpty) {
      return PdvPesquisaResolvida.vazia;
    }

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

    final codigoInterno = _buscarPorCodigoInternoExato(
      consulta,
      somenteAtivos: somenteAtivos,
    );
    if (codigoInterno != null) {
      return PdvPesquisaResolvida(
        produtos: [codigoInterno],
        totalCorrespondencias: 1,
        produtoAuto: codigoInterno,
        motivoAuto: PdvBuscaAutoMotivo.codigoInterno,
      );
    }

    final dupla = pesquisarPadraoPdv(
      consulta,
      clienteId: clienteId,
      limite: 2,
      somenteAtivos: somenteAtivos,
    );
    if (dupla.length == 1) {
      return PdvPesquisaResolvida(
        produtos: dupla,
        totalCorrespondencias: 1,
        produtoAuto: dupla.first,
        motivoAuto: PdvBuscaAutoMotivo.unicoResultado,
      );
    }
    if (dupla.length >= 2) {
      final lista = pesquisarPadraoPdv(
        consulta,
        clienteId: clienteId,
        limite: 50,
        somenteAtivos: somenteAtivos,
      );
      return PdvPesquisaResolvida(
        produtos: lista,
        totalCorrespondencias: lista.length >= 2 ? lista.length : 2,
      );
    }

    return const PdvPesquisaResolvida(
      produtos: [],
      totalCorrespondencias: 0,
    );
  }

  Produto? _buscarPorCodigoInternoExato(
    String termo, {
    required bool somenteAtivos,
  }) {
    _garantirCachesAtualizados();
    final norm = _normalizarTexto(termo.trim());
    if (norm.isEmpty) return null;
    for (final doc in _cacheDocs) {
      if (!_incluirDocNaPesquisa(
        doc,
        somenteAtivos: somenteAtivos,
        somenteInativos: false,
        excluirProdutosInternos: true,
      )) {
        continue;
      }
      if (doc.correspondeCodigoInterno(norm)) {
        return doc.produto;
      }
    }
    return null;
  }

  /// [pesquisarPadraoPdv] restrito a uma lista ja carregada (ex.: estoque).
  List<Produto> pesquisarNaBasePadraoPdv(
    String termo,
    Iterable<Produto> base, {
    int limite = 500,
    bool somenteAtivos = false,
    bool somenteInativos = false,
  }) {
    return pesquisarNaBase(
      termo,
      base,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    );
  }

  /// Aplica [pesquisar] sobre uma colecao ja carregada (mantem ordem do ranking).
  List<Produto> pesquisarNaBase(
    String termo,
    Iterable<Produto> base, {
    int limite = 500,
    bool somenteAtivos = false,
    bool somenteInativos = false,
    bool excluirProdutosInternos = true,
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
      excluirProdutosInternos: excluirProdutosInternos,
    ).where((p) => idsBase.contains(p.id)).toList();
  }

  /// Leitor de barras: retorna produto unico quando a consulta e GTIN completo.
  Produto? resolverLeitorCodigoBarras(
    String termo, {
    bool somenteAtivos = true,
  }) {
    if (!consultaPareceCodigoBarras(termo)) return null;
    return buscarPorCodigoBarras(termo, somenteAtivos: somenteAtivos);
  }

  void _garantirCachesAtualizados() {
    final agora = DateTime.now();
    final produtoCount = _db.produtoBox.count();
    final itemCount = _db.itemVendaBox.count();
    final vendaCount = _db.vendaBox.count();
    final ttlExpirado =
        _cacheMontadoEm == null ||
        agora.difference(_cacheMontadoEm!) > _cacheTtl;
    final estruturaMudou = produtoCount != _cacheProdutoCount;
    final historicoMudou =
        itemCount != _cacheItemCount || vendaCount != _cacheVendaCount;

    if (estruturaMudou || _cacheDocs.isEmpty || ttlExpirado) {
      _migrarCampoAtivoLegadoUmaVez();
      final produtos = _db.produtoBox.getAll();
      _normalizarDadosLegados(produtos);
      _cacheDocs = produtos.map(_criarDocBusca).toList();
      _cacheProdutoCount = produtoCount;
    }
    if (historicoMudou || ttlExpirado || _cacheScoreHistorico.isEmpty) {
      _cacheScoreHistorico = _pontuacaoPorHistoricoVendas();
      _cacheScoreCliente.clear();
      _cacheItemCount = itemCount;
      _cacheVendaCount = vendaCount;
    }
    _cacheMontadoEm = agora;
  }

  _ProdutoBuscaDoc _criarDocBusca(Produto produto) {
    final nome = _normalizarTexto(produto.nome);
    final descricao = _normalizarTexto(produto.descricao);
    final codigoInterno = _normalizarTexto(produto.codigoInterno);
    final codigoBarras = normalizarCodigoBarrasConsulta(produto.codigoBarras);
    final categoria = _normalizarTexto(produto.categoria);
    final subcategoria = _normalizarTexto(produto.subcategoria);
    final marca = _normalizarTexto(produto.marca);
    final fornecedor = _normalizarTexto(produto.fornecedor);
    final fabricante = _normalizarTexto(produto.fabricante);
    final apelidosBrutos = parseApelidosBusca(produto.apelidosBusca);
    final apelidosNormalizados = apelidosBrutos
        .map(_normalizarTexto)
        .where((a) => a.isNotEmpty)
        .toList();
    final codigosBarrasAlternativos = codigosBarrasAlternativosDeApelidos(
      apelidosBrutos,
    );
    final skuSemZeros = skuNumericoSemZerosEsquerda(produto.codigoInterno);
    final palavrasExtrasSku = <String>[];
    if (skuSemZeros != null &&
        skuSemZeros != somenteDigitosBusca(codigoInterno)) {
      palavrasExtrasSku.add(skuSemZeros);
    }
    final textoMedidas = [
      nome,
      descricao,
      codigoInterno,
      categoria,
      subcategoria,
      marca,
      ...apelidosNormalizados,
    ].join(' ');
    final tokensMedidas = extrairTokensMedidasDeTexto(textoMedidas);
    final textoCompleto = [
      nome,
      descricao,
      codigoInterno,
      codigoBarras,
      categoria,
      subcategoria,
      marca,
      fornecedor,
      fabricante,
      ...apelidosNormalizados,
      ...palavrasExtrasSku,
      ...tokensMedidas,
    ].join(' ');
    final palavras = textoCompleto
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    return _ProdutoBuscaDoc(
      produto: produto,
      nomeNormalizado: nome,
      nomeCompacto: compactarTextoBuscaObra(nome),
      descricaoNormalizada: descricao,
      codigoInternoNormalizado: codigoInterno,
      codigoBarrasNormalizado: codigoBarras,
      categoriaNormalizada: categoria,
      subcategoriaNormalizada: subcategoria,
      marcaNormalizada: marca,
      fornecedorNormalizado: fornecedor,
      fabricanteNormalizado: fabricante,
      apelidosNormalizados: apelidosNormalizados,
      codigosBarrasAlternativos: codigosBarrasAlternativos,
      palavrasBusca: palavras,
    );
  }

  Map<int, double> _pontuacaoPorHistoricoVendas() {
    final acumulado = <int, int>{};
    final vendaIds = _idsVendasFinalizadasRecentes();
    _acumularQuantidadeItensPorVendas(vendaIds, acumulado);
    final score = <int, double>{};
    acumulado.forEach((produtoId, qtd) {
      score[produtoId] = math.log(qtd + 1) * 18;
    });
    return score;
  }

  Map<int, double> _pontuacaoPorCliente(int clienteId) {
    final cacheado = _cacheScoreCliente[clienteId];
    if (cacheado != null) return cacheado;
    final acumulado = <int, int>{};
    final vendaIds = _idsVendasFinalizadasRecentes(clienteId: clienteId);
    _acumularQuantidadeItensPorVendas(vendaIds, acumulado);
    final score = <int, double>{};
    acumulado.forEach((produtoId, qtd) {
      score[produtoId] = math.log(qtd + 1) * 24;
    });
    if (_cacheScoreCliente.length >= 20) {
      _cacheScoreCliente.remove(_cacheScoreCliente.keys.first);
    }
    _cacheScoreCliente[clienteId] = score;
    return score;
  }

  static const _historicoVendasDias = 90;

  Set<int> _idsVendasFinalizadasRecentes({int? clienteId}) {
    final desde = DateTime.now()
        .subtract(const Duration(days: _historicoVendasDias))
        .toUtc();
    var cond = Venda_.status
        .equals('finalizada')
        .and(Venda_.cancelada.equals(false))
        .and(Venda_.data.greaterOrEqualDate(desde));
    if (clienteId != null && clienteId > 0) {
      cond = cond.and(Venda_.cliente.equals(clienteId));
    }
    final query = _db.vendaBox.query(cond).build();
    try {
      return query
          .find()
          .map((v) => v.id)
          .where((id) => id > 0)
          .toSet();
    } finally {
      query.close();
    }
  }

  void _acumularQuantidadeItensPorVendas(
    Set<int> vendaIds,
    Map<int, int> acumulado,
  ) {
    if (vendaIds.isEmpty) return;
    final lista = vendaIds.toList();
    const chunkSize = 48;
    for (var i = 0; i < lista.length; i += chunkSize) {
      final fim = math.min(i + chunkSize, lista.length);
      final chunk = lista.sublist(i, fim);
      var cond = ItemVenda_.venda.equals(chunk.first);
      for (var j = 1; j < chunk.length; j++) {
        cond = cond.or(ItemVenda_.venda.equals(chunk[j]));
      }
      final query = _db.itemVendaBox.query(cond).build();
      try {
        for (final item in query.find()) {
          final produto = item.produto.target;
          if (produto == null) continue;
          acumulado.update(
            produto.id,
            (atual) => atual + item.quantidade,
            ifAbsent: () => item.quantidade,
          );
        }
      } finally {
        query.close();
      }
    }
  }

  double _scoreProduto(
    _ProdutoBuscaDoc doc, {
    required String consultaNormalizada,
    required String consultaCompacta,
    required List<String> frasesConsulta,
    required List<String> tokensSignificativos,
    required List<String> tokensExpandidos,
    required List<String> palavrasObrigatorias,
    required double scoreHistoricoVenda,
    required double scoreCliente,
  }) {
    final nome = doc.nomeNormalizado;
    final nomeCompacto = doc.nomeCompacto;
    final descricao = doc.descricaoNormalizada;

    for (final palavra in palavrasObrigatorias) {
      if (!textoContemTokenObra(nome, palavra)) {
        return 0;
      }
    }
    final codigoInterno = doc.codigoInternoNormalizado;
    final codigoBarras = doc.codigoBarrasNormalizado;
    final consultaDigitos = somenteDigitosBusca(consultaNormalizada);
    final camposSecundarios = [
      doc.categoriaNormalizada,
      doc.subcategoriaNormalizada,
      doc.marcaNormalizada,
      doc.fornecedorNormalizado,
      doc.fabricanteNormalizado,
      descricao,
    ];

    double score = 0;

    if (doc.correspondeCodigoBarras(consultaDigitos) && consultaDigitos.isNotEmpty) {
      score += 1500;
    } else if (consultaDigitos.length >= 6 &&
        codigoBarras.isNotEmpty &&
        codigoBarras.endsWith(consultaDigitos)) {
      score += 900;
    }
    if (consultaNormalizada == codigoInterno && codigoInterno.isNotEmpty) {
      score += 1000;
    } else if (skuBuscaCorrespondeExato(consultaNormalizada, codigoInterno)) {
      score += 1000;
    } else {
      final skuParcial =
          skuBuscaPontuacaoParcial(consultaNormalizada, codigoInterno);
      if (skuParcial != null) {
        score += skuParcial;
      }
    }
    for (final apelido in doc.apelidosNormalizados) {
      if (apelido == consultaNormalizada) {
        score += 980;
      } else if (apelido.contains(consultaNormalizada) &&
          consultaNormalizada.length >= 3) {
        score += 520;
      }
    }
    if (consultaCompacta.length >= 5 &&
        nomeCompacto.contains(consultaCompacta)) {
      score += 1400;
    }
    for (final frase in frasesConsulta) {
      if (frase.length < 4) continue;
      if (nome.contains(frase)) {
        score += 620;
      } else {
        final fc = compactarTextoBuscaObra(frase);
        if (fc.length >= 4 && nomeCompacto.contains(fc)) {
          score += 580;
        }
      }
    }
    if (nome.startsWith(consultaNormalizada)) {
      score += 700;
    }
    if (nome.contains(consultaNormalizada)) {
      score += 450;
    }
    if (descricao.contains(consultaNormalizada) && consultaNormalizada.length >= 3) {
      score += 280;
    }
    if (doc.categoriaNormalizada.contains(consultaNormalizada) ||
        doc.marcaNormalizada.contains(consultaNormalizada)) {
      score += 200;
    }

    var tokensSigMatchNome = 0;
    var tokensSigMatch = 0;
    for (final token in tokensSignificativos) {
      if (token.isEmpty) continue;
      final noNome = textoContemTokenObra(nome, token);
      final noDescricao = textoContemTokenObra(descricao, token);
      if (noNome || noDescricao) {
        tokensSigMatch++;
        if (noNome) {
          tokensSigMatchNome++;
          score += token.contains('/') || token.contains('x') ? 240 : 180;
        } else {
          score += 70;
        }
      }
    }

    if (tokensSignificativos.length >= 2) {
      if (tokensSigMatchNome == tokensSignificativos.length) {
        score += 520;
      } else {
        final faltam = tokensSignificativos.length - tokensSigMatchNome;
        score -= 120.0 * faltam;
      }
      if (sequenciaTokensNoTexto(nome, tokensSignificativos)) {
        score += 380;
      }
    }

    var tokensExpMatch = 0;
    for (final token in tokensExpandidos) {
      var tokenMatched = false;
      if (token.isEmpty) continue;
      final tokenDigitos = somenteDigitosBusca(token);
      if (doc.correspondeCodigoBarras(tokenDigitos) && tokenDigitos.isNotEmpty) {
        score += 380;
        tokenMatched = true;
      } else if (skuBuscaCorrespondeExato(token, codigoInterno)) {
        score += 320;
        tokenMatched = true;
      } else if (codigoInterno == token) {
        score += 320;
        tokenMatched = true;
      } else if (doc.apelidosNormalizados.any(
        (a) => a == token || (a.contains(token) && token.length >= 3),
      )) {
        score += 260;
        tokenMatched = true;
      } else if (textoContemTokenObra(nome, token)) {
        score += token.length >= 4 || token.contains('/') ? 150 : 60;
        tokenMatched = true;
      } else if (camposSecundarios.any((c) => textoContemTokenObra(c, token))) {
        score += 50;
        tokenMatched = true;
      } else if (token.length >= 4) {
        final typo = _melhorDistanciaToken(token, doc.palavrasBusca);
        if (typo <= _limiteDistanciaTypos(token)) {
          score += 35;
          tokenMatched = true;
        }
      }
      if (tokenMatched) {
        tokensExpMatch++;
      }
    }

    if (tokensSignificativos.isNotEmpty &&
        tokensSigMatch == tokensSignificativos.length) {
      score += 120;
    } else if (tokensExpMatch == 0 && tokensSigMatch == 0) {
      return 0;
    }

    // Historico nao deve ultrapassar match forte de dimensao no nome.
    final bonusHistorico = score >= 900
        ? scoreHistoricoVenda * 0.35
        : scoreHistoricoVenda;
    final bonusCliente =
        score >= 900 ? scoreCliente * 0.35 : scoreCliente;

    if (doc.produto.estoqueReal > 0) {
      score += math.min(40, doc.produto.estoqueReal.toDouble());
    } else {
      score -= 80;
    }
    score += bonusHistorico;
    score += bonusCliente;

    return score;
  }

  int _limiteDistanciaTypos(String token) {
    if (token.length <= 4) return 1;
    if (token.length <= 8) return 2;
    return 3;
  }

  int _melhorDistanciaToken(String token, Iterable<String> palavras) {
    var melhor = 999;
    for (final palavra in palavras) {
      final d = _levenshtein(token, palavra);
      if (d < melhor) melhor = d;
      if (melhor == 0) return 0;
    }
    return melhor;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final curr = List<int>.filled(b.length + 1, 0);
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insert = curr[j - 1] + 1;
        final delete = prev[j] + 1;
        final replace =
            prev[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        curr[j] = math.min(math.min(insert, delete), replace);
      }
      prev = curr;
    }
    return prev[b.length];
  }

  String _normalizarTexto(String texto) {
    final lower = texto.toLowerCase().trim();
    if (lower.isEmpty) return '';
    final sb = StringBuffer();
    const mapa = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      sb.write(mapa[char] ?? char);
    }
    return sb.toString().replaceAll(RegExp(r'[^\w\s\/\-\+]'), ' ');
  }

  /// Persiste cadastro; alteracao de [Produto.estoqueReal] passa pelo gerenciador.
  int salvar(
    Produto produto, {
    String motivoAjusteEstoque = 'Ajuste manual cadastro produto',
    String usuarioAjusteEstoque = '',
  }) {
    produto.codigoInterno = normalizarCodigoInternoPersistido(
      produto.codigoInterno,
    );
    final nomeBruto = produto.nome;
    final nomeTitulo = ProdutoNomeTituloNormalizer.normalizar(nomeBruto);
    final impressaoBruta = produto.nomeImpressao.trim();
    // Se impressao seguia o nome antigo (ou vazia), acompanha o titulo novo.
    if (impressaoBruta.isEmpty ||
        impressaoBruta == nomeBruto.trim() ||
        impressaoBruta == nomeTitulo) {
      produto.nomeImpressao = nomeTitulo;
    }
    produto.nome = nomeTitulo;
    produto.nomeImpressao = ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
      nome: produto.nome,
      nomeImpressao: produto.nomeImpressao,
    );
    _garantirSkuUnico(produto);
    final id = _db.store.runInTransaction(TxMode.write, () {
      if (produto.id > 0) {
        final existente = _db.produtoBox.get(produto.id);
        if (existente == null) {
          throw StateError('Produto id ${produto.id} nao encontrado.');
        }
        final novoEstoque = produto.estoqueReal;
        _copiarCamposCadastro(existente, produto);
        final estoqueMudou = novoEstoque != existente.estoqueReal;
        if (!estoqueMudou) {
          existente.estoqueAtual = existente.estoqueReal;
        }
        // Cadastro antes do ajuste de estoque: o gerenciador recarrega o produto do banco.
        _db.produtoBox.put(existente);
        if (estoqueMudou) {
          _estoque.executarAjusteManualInventario(
            existente,
            novoEstoque,
            motivoAjusteEstoque,
            usuarioLogin: usuarioAjusteEstoque,
          );
        }
        return existente.id;
      }

      final estoqueInicial = produto.estoqueReal;
      produto.estoqueReal = 0;
      produto.estoqueAtual = 0;
      final novoId = _db.produtoBox.put(produto);
      produto.id = novoId;
      if (estoqueInicial > 0) {
        _estoque.executarAjusteManualInventario(
          produto,
          estoqueInicial,
          motivoAjusteEstoque,
          usuarioLogin: usuarioAjusteEstoque,
        );
      }
      return novoId;
    });
    if (_importacaoEmLoteDepth <= 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: id);
    }
    return id;
  }

  static void _copiarCamposCadastro(Produto destino, Produto origem) {
    destino.codigoInterno = origem.codigoInterno;
    destino.nome = origem.nome;
    destino.nomeImpressao = origem.nomeImpressao;
    destino.descricao = origem.descricao;
    destino.unidade = origem.unidade;
    destino.categoria = origem.categoria;
    destino.subcategoria = origem.subcategoria;
    destino.marca = origem.marca;
    destino.fornecedor = origem.fornecedor;
    destino.fabricante = origem.fabricante;
    destino.codigoBarras = origem.codigoBarras;
    destino.apelidosBusca = origem.apelidosBusca;
    destino.fotoPath = origem.fotoPath;
    destino.localizacao = origem.localizacao;
    destino.estoqueCd = origem.estoqueCd;
    destino.substitutosIds = origem.substitutosIds;
    destino.ncm = origem.ncm;
    destino.cest = origem.cest;
    destino.grupoTributario = origem.grupoTributario;
    destino.cfopVenda = origem.cfopVenda;
    destino.icmsOrigem = origem.icmsOrigem;
    destino.icmsSituacaoTributaria = origem.icmsSituacaoTributaria;
    destino.pisCofinsSituacaoTributaria = origem.pisCofinsSituacaoTributaria;
    destino.estoqueReservado = origem.estoqueReservado;
    destino.leadTimeDias = origem.leadTimeDias;
    destino.vendaMediaDiaria = origem.vendaMediaDiaria;
    destino.estoqueSeguranca = origem.estoqueSeguranca;
    destino.quantidadeMinima = origem.quantidadeMinima;
    destino.precoCusto = origem.precoCusto;
    destino.custoMedio = origem.custoMedio;
    destino.preco1 = origem.preco1;
    destino.preco2 = origem.preco2;
    destino.preco3 = origem.preco3;
    destino.precoVenda = origem.precoVenda;
    destino.limiteDescontoPreco1 = origem.limiteDescontoPreco1;
    destino.limiteDescontoPreco2 = origem.limiteDescontoPreco2;
    destino.limiteDescontoPreco3 = origem.limiteDescontoPreco3;
    destino.unidadeCompra = origem.unidadeCompra;
    destino.quantidadePorEmbalagem = origem.quantidadePorEmbalagem;
    destino.embalagemMultiplica = origem.embalagemMultiplica;
    destino.permiteQuantidadeFracionada = origem.permiteQuantidadeFracionada;
    destino.ultimaVendaEm = origem.ultimaVendaEm;
    destino.criadoEm = origem.criadoEm;
    destino.ativo = origem.ativo;
  }

  /// Remove zeros a esquerda de SKUs numericos legados (ex.: 008858 -> 8858).
  /// Pula produtos cujo SKU canonico ja pertence a outro cadastro.
  int migrarSkuZerosEsquerdaLegado() {
    final todos = _db.produtoBox.getAll();
    if (todos.isEmpty) return 0;

    var alterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in todos) {
        final atual = p.codigoInterno.trim();
        if (atual.isEmpty) continue;
        final novo = normalizarCodigoInternoPersistido(atual);
        if (novo == atual) continue;

        final novoLower = novo.toLowerCase();
        final conflito = todos.any(
          (outro) =>
              outro.id != p.id &&
              outro.codigoInterno.trim().toLowerCase() == novoLower,
        );
        if (conflito) {
          debugPrint(
            'Migracao SKU: pulando produto ${p.id} ($atual -> $novo) — SKU ja em uso.',
          );
          continue;
        }

        p.codigoInterno = novo;
        _db.produtoBox.put(p);
        alterados++;
      }
    });

    if (alterados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      debugPrint('Migracao SKU: $alterados produto(s) normalizado(s).');
    }
    return alterados;
  }

  /// Aplica o mesmo [fotoPath] a varios produtos (ex.: foto em lote na pesquisa).
  int aplicarFotoEmVarios({
    required Iterable<int> ids,
    required String fotoPath,
  }) {
    final path = fotoPath.trim();
    if (path.isEmpty) return 0;
    final unicos = ids.where((id) => id > 0).toSet();
    if (unicos.isEmpty) return 0;
    final alteradosIds = <int>[];
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in unicos) {
        final p = _db.produtoBox.get(id);
        if (p == null) continue;
        if (p.fotoPath.trim() == path) continue;
        p.fotoPath = path;
        _db.produtoBox.put(p);
        alteradosIds.add(id);
      }
    });
    for (final id in alteradosIds) {
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: id);
    }
    if (alteradosIds.isNotEmpty) {
      invalidarCacheBusca();
    }
    return alteradosIds.length;
  }

  bool remover(int id) {
    final ok = _db.produtoBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('produto', id);
      invalidarCacheBusca();
    }
    return ok;
  }

  /// Exclui varios produtos de uma vez (cadastro / limpeza).
  /// Retorna quantos foram removidos com sucesso.
  int removerVarios(Iterable<int> ids) {
    final unicos = ids.where((id) => id > 0).toSet().toList();
    if (unicos.isEmpty) return 0;
    final removidosIds = <int>[];
    _db.store.runInTransaction(TxMode.write, () {
      for (final id in unicos) {
        if (_db.produtoBox.remove(id)) {
          removidosIds.add(id);
        }
      }
    });
    for (final id in removidosIds) {
      registrarDeleteParaRede('produto', id);
    }
    if (removidosIds.isNotEmpty) {
      invalidarCacheBusca();
    }
    return removidosIds.length;
  }

  /// Converte nomes em MAIUSCULO para titulo (ex.: Abracadeira de Nylon…).
  ///
  /// Atualiza tambem [Produto.nomeImpressao] quando ele era igual ao nome antigo
  /// ou estava vazio.
  ({int alterados, int inalterados}) padronizarNomesTituloEmLote() {
    var alterados = 0;
    var inalterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final p in _db.produtoBox.getAll()) {
        final nomeAntigo = p.nome;
        final impressaoAntiga = p.nomeImpressao.trim();
        final nomeNovo = ProdutoNomeTituloNormalizer.normalizar(nomeAntigo);
        if (nomeNovo.isEmpty || nomeNovo == nomeAntigo.trim()) {
          inalterados++;
          continue;
        }
        p.nome = nomeNovo;
        if (impressaoAntiga.isEmpty || impressaoAntiga == nomeAntigo.trim()) {
          p.nomeImpressao = nomeNovo;
        } else {
          p.nomeImpressao = ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
            nome: nomeNovo,
            nomeImpressao: impressaoAntiga,
          );
        }
        _db.produtoBox.put(p);
        alterados++;
      }
    });
    if (alterados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return (alterados: alterados, inalterados: inalterados);
  }

  /// Quantos produtos apontam para o mesmo arquivo de foto.
  int contarProdutosComFotoPath(
    String imagePath, {
    int? excluirProdutoId,
  }) {
    final alvo = imagePath.trim();
    if (alvo.isEmpty) return 0;
    final alvoAbs = p.normalize(File(alvo).absolute.path);
    final alvoBase = p.basename(alvoAbs);
    var n = 0;
    for (final pr in _db.produtoBox.getAll()) {
      if (excluirProdutoId != null && pr.id == excluirProdutoId) continue;
      final fp = pr.fotoPath.trim();
      if (fp.isEmpty) continue;
      final fpAbs = p.normalize(File(fp).absolute.path);
      if (fpAbs == alvoAbs || p.basename(fpAbs) == alvoBase) {
        n++;
      }
    }
    return n;
  }

  /// Converte fotoPath absoluto (outro PC) para basename de imagem.
  int normalizarFotoPathsParaSyncLan() {
    var alterados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final pr in _db.produtoBox.getAll()) {
        final raw = pr.fotoPath.trim();
        if (raw.isEmpty) continue;
        final nome = ProdutoImagemNomeArquivo.extrairNomeParaLan(raw);
        if (nome == null || nome == raw) continue;
        pr.fotoPath = nome;
        _db.produtoBox.put(pr);
        alterados++;
      }
    });
    if (alterados > 0) {
      invalidarCacheBusca();
    }
    return alterados;
  }

  /// Une fotos com o mesmo conteudo em um unico arquivo e atualiza os produtos.
  Future<({int produtosAtualizados, int arquivosRemovidos})>
      consolidarFotosDuplicadas() async {
    final produtos = _db.produtoBox.getAll();
    final pares = <({int id, String fotoPath})>[
      for (final pr in produtos)
        if (pr.fotoPath.trim().isNotEmpty)
          (id: pr.id, fotoPath: pr.fotoPath.trim()),
    ];
    if (pares.isEmpty) {
      return (produtosAtualizados: 0, arquivosRemovidos: 0);
    }

    final svc = ProdutoImagemService(imagesDirectoryPath: productImagesDirPath);
    final resultado = await svc.consolidarImagensDuplicadas(pares);
    if (resultado.novosPaths.isEmpty) {
      return (
        produtosAtualizados: 0,
        arquivosRemovidos: resultado.arquivosRemovidos,
      );
    }

    var atualizados = 0;
    _db.store.runInTransaction(TxMode.write, () {
      for (final entry in resultado.novosPaths.entries) {
        final pr = _db.produtoBox.get(entry.key);
        if (pr == null) continue;
        pr.fotoPath = entry.value;
        _db.produtoBox.put(pr);
        atualizados++;
      }
    });
    if (atualizados > 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return (
      produtosAtualizados: atualizados,
      arquivosRemovidos: resultado.arquivosRemovidos,
    );
  }

  /// Remove todos os produtos do cadastro para reimportacao do zero.
  ///
  /// Mantem vendas, clientes, usuarios e itens historicos de venda.
  /// Limpa dados satelites do catalogo (movimentos, historico de entrada,
  /// kits, promocões, sugestoes, vinculos e lista de compras).
  Future<ProdutoCadastroZerarResultado> zerarCadastroCompleto({
    bool limparImagens = true,
  }) async {
    final produtos = _db.produtoBox.getAll();
    final ids = produtos.map((p) => p.id).where((id) => id > 0).toList();
    final total = ids.length;

    final imagensRemovidas = limparImagens
        ? await _limparPastaImagensProdutos()
        : 0;

    var movimentos = 0;
    var historicos = 0;
    var vinculos = 0;
    var kits = 0;
    var kitItens = 0;
    var promocoes = 0;
    var promoItens = 0;
    var promoCombos = 0;
    var sugestoes = 0;
    var metricasSugestao = 0;
    var listaCompras = 0;

    _db.store.runInTransaction(TxMode.write, () {
      historicos = _db.historicoEntradaBox.removeAll();
      movimentos = _db.movimentoEstoqueBox.removeAll();
      vinculos = _db.vinculoFornecedorProdutoBox.removeAll();
      kitItens = _db.kitOrcamentoItemBox.removeAll();
      kits = _db.kitOrcamentoBox.removeAll();
      promoItens = _db.promocaoItemBox.removeAll();
      promoCombos = _db.promocaoComboItemBox.removeAll();
      promocoes = _db.promocaoBox.removeAll();
      sugestoes = _db.produtoSugestaoVendaBox.removeAll();
      metricasSugestao = _db.sugestaoVendaMetricaEventoBox.removeAll();
      listaCompras = _db.itemListaCompraBox.removeAll();
      _db.produtoBox.removeAll();
    });

    if (ids.isNotEmpty) {
      await SyncDeleteOutbox.registrarVarios(
        entity: 'produto',
        entityIds: ids,
      );
      await SyncDirtyOutbox.removerVarios(
        entity: 'produto',
        entityIds: ids,
      );
    }
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);

    return ProdutoCadastroZerarResultado(
      produtosRemovidos: total,
      movimentosRemovidos: movimentos,
      historicosEntradaRemovidos: historicos,
      vinculosRemovidos: vinculos,
      kitsRemovidos: kits,
      kitItensRemovidos: kitItens,
      promocoesRemovidas: promocoes,
      promocaoItensRemovidos: promoItens,
      promocaoCombosRemovidos: promoCombos,
      sugestoesRemovidas: sugestoes,
      metricasSugestaoRemovidas: metricasSugestao,
      itensListaCompraRemovidos: listaCompras,
      imagensRemovidas: imagensRemovidas,
    );
  }

  Future<int> _limparPastaImagensProdutos() async {
    final dir = _db.productImagesDir;
    if (!dir.existsSync()) return 0;
    var removidas = 0;
    for (final entity in dir.listSync()) {
      try {
        if (entity is File) {
          await entity.delete();
          removidas++;
        }
      } catch (_) {
        // Melhor esforco: cadastro ja foi limpo.
      }
    }
    return removidas;
  }

  /// Remove cadastros duplicados do mesmo codigo interno (mantem 1 por SKU).
  ///
  /// Criterio do sobrevivente: maior estoque, depois menor id (mais antigo).
  /// Retorna quantos registros foram removidos.
  Future<int> deduplicarProdutosMesmoSku({bool notificarRede = true}) async {
    final porSku = <String, List<Produto>>{};
    for (final p in _db.produtoBox.getAll()) {
      final sku = p.codigoInterno.trim().toLowerCase();
      if (sku.isEmpty) continue;
      (porSku[sku] ??= <Produto>[]).add(p);
    }

    final gruposDup = <List<Produto>>[];
    for (final g in porSku.values) {
      if (g.length < 2) continue;
      g.sort((a, b) {
        final estoque = b.estoqueReal.compareTo(a.estoqueReal);
        if (estoque != 0) return estoque;
        return a.id.compareTo(b.id);
      });
      gruposDup.add(g);
    }
    if (gruposDup.isEmpty) return 0;

    final idsDup = <int>[
      for (final g in gruposDup)
        for (var i = 1; i < g.length; i++) g[i].id,
    ];
    if (idsDup.isEmpty) return 0;

    // Query por ToOne (nao varre todas as vendas da loja).
    final qItens = _db.itemVendaBox
        .query(ItemVenda_.produto.oneOf(idsDup))
        .build();
    final qHist = _db.historicoEntradaBox
        .query(HistoricoEntrada_.produto.oneOf(idsDup))
        .build();
    final qMov = _db.movimentoEstoqueBox
        .query(MovimentoEstoque_.produto.oneOf(idsDup))
        .build();
    final qVinc = _db.vinculoFornecedorProdutoBox
        .query(VinculoFornecedorProduto_.produto.oneOf(idsDup))
        .build();
    final qLista = _db.itemListaCompraBox
        .query(ItemListaCompra_.produto.oneOf(idsDup))
        .build();
    late final List<ItemVenda> itensVenda;
    late final List<HistoricoEntrada> historicos;
    late final List<MovimentoEstoque> movimentos;
    late final List<VinculoFornecedorProduto> vinculos;
    late final List<ItemListaCompra> listaCompra;
    try {
      itensVenda = qItens.find();
      historicos = qHist.find();
      movimentos = qMov.find();
      vinculos = qVinc.find();
      listaCompra = qLista.find();
    } finally {
      qItens.close();
      qHist.close();
      qMov.close();
      qVinc.close();
      qLista.close();
    }

    final keeperPorDupId = <int, Produto>{};
    final removidos = <int>[];

    _db.store.runInTransaction(TxMode.write, () {
      for (final grupo in gruposDup) {
        final keeper = grupo.first;
        for (var i = 1; i < grupo.length; i++) {
          final dup = grupo[i];
          keeperPorDupId[dup.id] = keeper;
          if (dup.estoqueReal != 0) {
            keeper.estoqueReal += dup.estoqueReal;
            keeper.estoqueAtual = keeper.estoqueReal;
            keeper.estoqueVersao++;
            _db.produtoBox.put(keeper);
          }
          _db.produtoBox.remove(dup.id);
          removidos.add(dup.id);
        }
      }

      for (final item in itensVenda) {
        final k = keeperPorDupId[item.produto.targetId];
        if (k == null) continue;
        item.produto.target = k;
        _db.itemVendaBox.put(item);
      }
      for (final h in historicos) {
        final k = keeperPorDupId[h.produto.targetId];
        if (k == null) continue;
        h.produto.target = k;
        _db.historicoEntradaBox.put(h);
      }
      for (final mv in movimentos) {
        final k = keeperPorDupId[mv.produto.targetId];
        if (k == null) continue;
        mv.produto.target = k;
        _db.movimentoEstoqueBox.put(mv);
      }
      for (final v in vinculos) {
        final k = keeperPorDupId[v.produto.targetId];
        if (k == null) continue;
        v.produto.target = k;
        _db.vinculoFornecedorProdutoBox.put(v);
      }
      for (final item in listaCompra) {
        final k = keeperPorDupId[item.produto.targetId];
        if (k == null) continue;
        item.produto.target = k;
        _db.itemListaCompraBox.put(item);
      }
    });

    if (removidos.isEmpty) return 0;

    invalidarCacheBusca();
    await SyncDeleteOutbox.registrarVarios(
      entity: 'produto',
      entityIds: removidos,
    );
    if (notificarRede) {
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
    return removidos.length;
  }

  Produto? obterPorId(int id) => _db.produtoBox.get(id);

  /// Busca por codigo interno (literal ou numerico sem zeros a esquerda).
  Produto? obterPorCodigoInterno(String codigo, {int? ignorarProdutoId}) {
    final lista = listarPorCodigoInterno(
      codigo,
      ignorarProdutoId: ignorarProdutoId,
    );
    return lista.isEmpty ? null : lista.first;
  }

  /// Todos os produtos com o mesmo SKU (detecta duplicatas reais).
  List<Produto> listarPorCodigoInterno(
    String codigo, {
    int? ignorarProdutoId,
  }) {
    final alvo = codigo.trim();
    if (alvo.isEmpty) return const [];
    _garantirCachesAtualizados();
    final norm = _normalizarTexto(alvo);
    final out = <Produto>[];
    for (final doc in _cacheDocs) {
      final p = doc.produto;
      if (ignorarProdutoId != null && p.id == ignorarProdutoId) continue;
      if (doc.correspondeCodigoInterno(norm)) out.add(p);
    }
    return out;
  }

  /// SKU automatico curto para PDV: 1, 2, 3… apos o maior numerico ja cadastrado.
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

  void _garantirSkuUnico(Produto produto) {
    final sku = produto.codigoInterno.trim();
    if (sku.isEmpty) return;
    final conflito = obterPorCodigoInterno(
      sku,
      ignorarProdutoId: produto.id > 0 ? produto.id : null,
    );
    if (conflito != null) {
      throw ProdutoSkuDuplicadoException(
        sku: sku,
        produtoExistenteNome: conflito.nome,
        produtoExistenteId: conflito.id,
      );
    }
  }

  /// Entradas por importacao de NF-e, mais recentes primeiro.
  List<HistoricoEntrada> listarHistoricoEntradaPorProduto(int produtoId) {
    final q = _db.historicoEntradaBox
        .query(HistoricoEntrada_.produto.equals(produtoId))
        .order(HistoricoEntrada_.dataEmissao, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Data da NF-e de entrada mais recente, se houver.
  DateTime? obterDataUltimaCompraProduto(int produtoId) {
    final entradas = listarHistoricoEntradaPorProduto(produtoId);
    if (entradas.isEmpty) return null;
    return entradas.first.dataEmissao;
  }

  /// Kardex de movimentacoes de estoque, mais recentes primeiro.
  List<MovimentoEstoque> listarMovimentosEstoquePorProduto(
    int produtoId, {
    int limite = 200,
  }) =>
      MovimentoEstoqueRepository(_db).listarPorProduto(
        produtoId,
        limite: limite,
      );

  /// Ajuste manual de inventario com registro no kardex.
  void ajustarEstoqueManual({
    required int produtoId,
    required int novaQuantidadeFisica,
    required String motivo,
    String usuarioLogin = '',
  }) {
    _db.store.runInTransaction(TxMode.write, () {
      final produto = _db.produtoBox.get(produtoId);
      if (produto == null) {
        throw StateError('Produto id $produtoId nao encontrado.');
      }
      _estoque.executarAjusteManualInventario(
        produto,
        novaQuantidadeFisica,
        motivo,
        usuarioLogin: usuarioLogin,
      );
    });
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: produtoId);
  }

  /// Media ponderada das entradas de NF-e; null se nao houver historico valido.
  double? calcularCustoMedioPonderadoPorEntradasNfe(int produtoId) =>
      calcularCustoMedioPonderadoEntradasNfe(_db, produtoId);

  /// Atualiza [Produto.custoMedio]: prioridade entradas NF-e; senao [legadoImportacao];
  /// senao [Produto.precoCusto].
  void sincronizarCustoMedioInteligenteParaProduto(
    int produtoId, {
    double? legadoImportacao,
  }) {
    final p = _db.produtoBox.get(produtoId);
    if (p == null) return;
    final cm = calcularCustoMedioPonderadoEntradasNfe(_db, produtoId);
    if (cm != null) {
      p.custoMedio = cm;
    } else if (legadoImportacao != null && legadoImportacao > 0) {
      p.custoMedio = legadoImportacao;
    } else {
      p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
    }
    _db.produtoBox.put(p);
    if (_importacaoEmLoteDepth <= 0) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: produtoId);
    }
  }

  /// Recalcula custo medio para varios produtos (uma notificacao ao final).
  void sincronizarCustoMedioInteligenteParaProdutos(
    Iterable<int> produtoIds, {
    Map<int, double>? legadoImportacaoPorId,
  }) {
    final vistos = <int>{};
    for (final id in produtoIds) {
      if (id <= 0 || vistos.contains(id)) continue;
      vistos.add(id);
      final p = _db.produtoBox.get(id);
      if (p == null) continue;
      final legado = legadoImportacaoPorId?[id];
      final cm = calcularCustoMedioPonderadoEntradasNfe(_db, id);
      if (cm != null) {
        p.custoMedio = cm;
      } else if (legado != null && legado > 0) {
        p.custoMedio = legado;
      } else {
        p.custoMedio = p.precoCusto < 0 ? 0 : p.precoCusto;
      }
      _db.produtoBox.put(p);
    }
    if (vistos.isNotEmpty) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
    }
  }

  /// Executa gravacoes em massa sem rebuild de cache/notificacao a cada item.
  Future<T> executarImportacaoEmLote<T>(Future<T> Function() acao) async {
    _importacaoEmLoteDepth++;
    enterSyncApplySilencioso();
    try {
      return await acao();
    } finally {
      leaveSyncApplySilencioso();
      _importacaoEmLoteDepth--;
      if (_importacaoEmLoteDepth <= 0) {
        invalidarCacheBusca();
        notificarAlteracaoParaRede(entidade: 'produto', entidadeId: 0);
      }
    }
  }

  void _invalidarCacheBusca() {
    _cacheDocs = const [];
    _cacheScoreHistorico = const {};
    _cacheScoreCliente.clear();
    _cacheProdutoCount = -1;
    _cacheItemCount = -1;
    _cacheVendaCount = -1;
    _cacheMontadoEm = null;
  }

  /// Atualiza estoque nos docs em cache sem rebuild completo do catalogo.
  void _sincronizarEstoqueNosDocsCache() {
    if (_cacheDocs.isEmpty) return;
    for (final doc in _cacheDocs) {
      final id = doc.produto.id;
      if (id <= 0) continue;
      final fresh = _db.produtoBox.get(id);
      if (fresh == null) continue;
      doc.produto.estoqueReal = fresh.estoqueReal;
      doc.produto.estoqueReservado = fresh.estoqueReservado;
      doc.produto.estoqueAtual = fresh.estoqueAtual;
    }
  }

  /// Apos venda/entrega: estoque e historico mudaram, mas o catalogo de busca
  /// (nomes, barras, etc.) continua valido. Evita wipe + [notifyListeners]
  /// a cada escrita — o gargalo do PDV com catalogo grande.
  void atualizarCacheAposMovimentoEstoque() {
    _sincronizarEstoqueNosDocsCache();
    // Força recálculo lazy dos scores de historico na proxima busca.
    _cacheItemCount = -1;
    _cacheVendaCount = -1;
    _cacheScoreHistorico = const {};
    _cacheScoreCliente.clear();
  }

  /// Chamado apos operacoes que alteram cadastro/estrutura do catalogo
  /// (salvar produto, sync de produtos, importacao, etc.).
  void invalidarCacheBusca() {
    _invalidarCacheBusca();
    notifyListeners();
  }
}

class _ProdutoBuscaDoc {
  const _ProdutoBuscaDoc({
    required this.produto,
    required this.nomeNormalizado,
    required this.nomeCompacto,
    required this.descricaoNormalizada,
    required this.codigoInternoNormalizado,
    required this.codigoBarrasNormalizado,
    required this.categoriaNormalizada,
    required this.subcategoriaNormalizada,
    required this.marcaNormalizada,
    required this.fornecedorNormalizado,
    required this.fabricanteNormalizado,
    required this.apelidosNormalizados,
    required this.codigosBarrasAlternativos,
    required this.palavrasBusca,
  });

  final Produto produto;
  final String nomeNormalizado;
  final String nomeCompacto;
  final String descricaoNormalizada;
  final String codigoInternoNormalizado;
  final String codigoBarrasNormalizado;
  final String categoriaNormalizada;
  final String subcategoriaNormalizada;
  final String marcaNormalizada;
  final String fornecedorNormalizado;
  final String fabricanteNormalizado;
  final List<String> apelidosNormalizados;
  final List<String> codigosBarrasAlternativos;
  final List<String> palavrasBusca;

  bool correspondeCodigoInterno(String consultaNormalizada) {
    if (codigoInternoNormalizado.isEmpty || consultaNormalizada.isEmpty) {
      return false;
    }
    if (consultaNormalizada == codigoInternoNormalizado) return true;
    return skuBuscaCorrespondeExato(
      consultaNormalizada,
      codigoInternoNormalizado,
    );
  }

  bool correspondeCodigoBarras(String digitos) {
    if (digitos.isEmpty) return false;
    if (codigoBarrasNormalizado == digitos) return true;
    return codigosBarrasAlternativos.contains(digitos);
  }
}

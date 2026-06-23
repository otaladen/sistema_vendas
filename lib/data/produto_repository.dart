import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/historico_entrada.dart';
import '../model/movimento_estoque.dart';
import '../model/produto.dart';
import '../domain/produto_nome_exibicao.dart';
import '../services/gerenciador_estoque_service.dart';
import 'movimento_estoque_repository.dart';
import 'produto_busca_sinonimos.dart';
import 'produto_busca_util.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

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
      return docs.map((d) => d.produto).take(limite).toList();
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

    return resultados.map((d) => d.produto).take(limite).toList();
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

    return resultados.map((d) => d.produto).take(limite).toList();
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
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
  }) {
    return pesquisar(
      termo,
      clienteId: clienteId,
      limite: limite,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: true,
    );
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
    final itens = _db.itemVendaBox.getAll();
    final acumulado = <int, int>{};
    for (final item in itens) {
      final venda = item.venda.target;
      final produto = item.produto.target;
      if (venda == null || produto == null) continue;
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      acumulado.update(
        produto.id,
        (atual) => atual + item.quantidade,
        ifAbsent: () => item.quantidade,
      );
    }
    final score = <int, double>{};
    acumulado.forEach((produtoId, qtd) {
      score[produtoId] = math.log(qtd + 1) * 18;
    });
    return score;
  }

  Map<int, double> _pontuacaoPorCliente(int clienteId) {
    final cacheado = _cacheScoreCliente[clienteId];
    if (cacheado != null) return cacheado;
    final itens = _db.itemVendaBox.getAll();
    final acumulado = <int, int>{};
    for (final item in itens) {
      final venda = item.venda.target;
      final produto = item.produto.target;
      if (venda == null || produto == null) continue;
      if (venda.status != 'finalizada' || venda.cancelada) continue;
      if (venda.cliente.targetId != clienteId) continue;
      acumulado.update(
        produto.id,
        (atual) => atual + item.quantidade,
        ifAbsent: () => item.quantidade,
      );
    }
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
    produto.nomeImpressao = ProdutoNomeExibicao.normalizarNomeImpressaoPersistido(
      nome: produto.nome,
      nomeImpressao: produto.nomeImpressao,
    );
    final id = _db.store.runInTransaction(TxMode.write, () {
      if (produto.id > 0) {
        final existente = _db.produtoBox.get(produto.id);
        if (existente == null) {
          throw StateError('Produto id ${produto.id} nao encontrado.');
        }
        final novoEstoque = produto.estoqueReal;
        _copiarCamposCadastro(existente, produto);
        if (novoEstoque != existente.estoqueReal) {
          _estoque.executarAjusteManualInventario(
            existente,
            novoEstoque,
            motivoAjusteEstoque,
            usuarioLogin: usuarioAjusteEstoque,
          );
        } else {
          existente.estoqueAtual = existente.estoqueReal;
          _db.produtoBox.put(existente);
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
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: id);
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

  bool remover(int id) {
    final ok = _db.produtoBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('produto', id);
      invalidarCacheBusca();
    }
    return ok;
  }

  Produto? obterPorId(int id) => _db.produtoBox.get(id);

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
    invalidarCacheBusca();
    notificarAlteracaoParaRede(entidade: 'produto', entidadeId: produtoId);
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

  void _invalidarCacheBusca() {
    _cacheDocs = const [];
    _cacheScoreHistorico = const {};
    _cacheScoreCliente.clear();
    _cacheProdutoCount = -1;
    _cacheItemCount = -1;
    _cacheVendaCount = -1;
    _cacheMontadoEm = null;
  }

  /// Chamado apos operacoes que alteram [Produto.estoqueReal] / [Produto.estoqueReservado]
  /// fora deste repositorio (ex.: finalizacao de venda, checklist de entrega).
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

  bool correspondeCodigoBarras(String digitos) {
    if (digitos.isEmpty) return false;
    if (codigoBarrasNormalizado == digitos) return true;
    return codigosBarrasAlternativos.contains(digitos);
  }
}

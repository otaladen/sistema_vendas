import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../model/historico_entrada.dart';
import '../model/produto.dart';
import 'produto_busca_sinonimos.dart';
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
  ProdutoRepository(this._db);

  final ObjectBox _db;

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
      notificarAlteracaoParaRede();
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
    notificarAlteracaoParaRede();
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
  }) {
    _migrarCampoAtivoLegadoUmaVez();
    _garantirCachesAtualizados();
    final consultaBruta = termo.trim();
    final consultaNormalizada = _normalizarTexto(consultaBruta);
    final tokensBase = _tokenizar(consultaNormalizada);
    final tokens =
        expandirTokensBuscaComSinonimos(tokensBase).toSet().toList();
    if (consultaNormalizada.isEmpty) {
      final ordenados = [..._cacheDocs]
        ..sort((a, b) => a.nomeNormalizado.compareTo(b.nomeNormalizado));
      List<_ProdutoBuscaDoc> docs;
      if (somenteInativos) {
        docs = ordenados.where((d) => !d.produto.ativo).toList();
      } else if (somenteAtivos) {
        docs = ordenados.where((d) => d.produto.ativo).toList();
      } else {
        docs = ordenados;
      }
      return docs.map((d) => d.produto).take(limite).toList();
    }

    final scorePorProduto = <int, double>{};
    final scoreCliente = clienteId == null
        ? const <int, double>{}
        : _pontuacaoPorCliente(clienteId);

    for (final doc in _cacheDocs) {
      if (somenteInativos) {
        if (doc.produto.ativo) continue;
      } else if (somenteAtivos && !doc.produto.ativo) {
        continue;
      }
      final score = _scoreProduto(
        doc,
        consultaNormalizada: consultaNormalizada,
        tokens: tokens,
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
    final codigoInterno = _normalizarTexto(produto.codigoInterno);
    final codigoBarras = _normalizarTexto(produto.codigoBarras);
    final categoria = _normalizarTexto(produto.categoria);
    final marca = _normalizarTexto(produto.marca);
    final fornecedor = _normalizarTexto(produto.fornecedor);
    final fabricante = _normalizarTexto(produto.fabricante);
    final textoCompleto = [
      nome,
      codigoInterno,
      codigoBarras,
      categoria,
      marca,
      fornecedor,
      fabricante,
    ].join(' ');
    final palavras = textoCompleto
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    return _ProdutoBuscaDoc(
      produto: produto,
      nomeNormalizado: nome,
      codigoInternoNormalizado: codigoInterno,
      codigoBarrasNormalizado: codigoBarras,
      categoriaNormalizada: categoria,
      marcaNormalizada: marca,
      fornecedorNormalizado: fornecedor,
      fabricanteNormalizado: fabricante,
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
    required List<String> tokens,
    required double scoreHistoricoVenda,
    required double scoreCliente,
  }) {
    final nome = doc.nomeNormalizado;
    final codigoInterno = doc.codigoInternoNormalizado;
    final codigoBarras = doc.codigoBarrasNormalizado;
    final camposSecundarios = [
      doc.categoriaNormalizada,
      doc.marcaNormalizada,
      doc.fornecedorNormalizado,
      doc.fabricanteNormalizado,
    ];

    double score = 0;

    if (consultaNormalizada == codigoBarras && codigoBarras.isNotEmpty) {
      score += 1200;
    }
    if (consultaNormalizada == codigoInterno && codigoInterno.isNotEmpty) {
      score += 1000;
    }
    if (nome.startsWith(consultaNormalizada)) {
      score += 700;
    }
    if (nome.contains(consultaNormalizada)) {
      score += 450;
    }
    if (doc.categoriaNormalizada.contains(consultaNormalizada) ||
        doc.marcaNormalizada.contains(consultaNormalizada)) {
      score += 200;
    }

    var tokensComMatchForte = 0;
    for (final token in tokens) {
      var tokenMatched = false;
      if (token.isEmpty) continue;
      if (codigoBarras == token || codigoInterno == token) {
        score += 320;
        tokenMatched = true;
      } else if (nome.startsWith(token)) {
        score += 190;
        tokenMatched = true;
      } else if (nome.contains(token)) {
        score += 120;
        tokenMatched = true;
      } else if (camposSecundarios.any((c) => c.contains(token))) {
        score += 80;
        tokenMatched = true;
      } else {
        final typo = _melhorDistanciaToken(token, doc.palavrasBusca);
        if (typo <= _limiteDistanciaTypos(token)) {
          score += 45;
          tokenMatched = true;
        }
      }
      if (tokenMatched) {
        tokensComMatchForte++;
      }
    }

    if (tokens.isNotEmpty && tokensComMatchForte == tokens.length) {
      score += 90;
    } else if (tokensComMatchForte == 0) {
      return 0;
    }

    if (doc.produto.estoqueReal > 0) {
      score += math.min(40, doc.produto.estoqueReal.toDouble());
    } else {
      score -= 80;
    }
    score += scoreHistoricoVenda;
    score += scoreCliente;

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

  List<String> _tokenizar(String texto) {
    return texto
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
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

  int salvar(Produto produto) {
    produto.estoqueAtual = produto.estoqueReal;
    final id = _db.produtoBox.put(produto);
    invalidarCacheBusca();
    notificarAlteracaoParaRede();
    return id;
  }

  bool remover(int id) {
    final ok = _db.produtoBox.remove(id);
    if (ok) {
      invalidarCacheBusca();
      notificarAlteracaoParaRede();
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
    notificarAlteracaoParaRede();
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
      notificarAlteracaoParaRede();
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
    required this.codigoInternoNormalizado,
    required this.codigoBarrasNormalizado,
    required this.categoriaNormalizada,
    required this.marcaNormalizada,
    required this.fornecedorNormalizado,
    required this.fabricanteNormalizado,
    required this.palavrasBusca,
  });

  final Produto produto;
  final String nomeNormalizado;
  final String codigoInternoNormalizado;
  final String codigoBarrasNormalizado;
  final String categoriaNormalizada;
  final String marcaNormalizada;
  final String fornecedorNormalizado;
  final String fabricanteNormalizado;
  final List<String> palavrasBusca;
}

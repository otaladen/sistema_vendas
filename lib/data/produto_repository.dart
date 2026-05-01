import 'dart:math' as math;

import '../model/produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

class ProdutoRepository {
  ProdutoRepository(this._db);

  final ObjectBox _db;
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

  String get productImagesDirPath => _db.productImagesDir.path;

  List<Produto> listarTodos() {
    final query = _db.produtoBox.query().order(Produto_.nome).build();
    final produtos = query.find();
    query.close();
    _normalizarDadosLegados(produtos);
    return produtos;
  }

  void _normalizarDadosLegados(List<Produto> produtos) {
    for (final produto in produtos) {
      final unidade = produto.unidade.trim();
      final unidadeValida = _unidadesValidas.contains(unidade);
      bool houveAjuste = false;
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
      if (houveAjuste) {
        _db.produtoBox.put(produto);
      }
    }
  }

  List<Produto> pesquisar(
    String termo, {
    int? clienteId,
    int limite = 50,
  }) {
    _garantirCachesAtualizados();
    final consultaBruta = termo.trim();
    final consultaNormalizada = _normalizarTexto(consultaBruta);
    final tokensBase = _tokenizar(consultaNormalizada);
    final tokens = _expandirTokensComSinonimos(tokensBase).toSet().toList();
    if (consultaNormalizada.isEmpty) {
      final ordenados = [..._cacheDocs]
        ..sort((a, b) => a.nomeNormalizado.compareTo(b.nomeNormalizado));
      return ordenados.map((d) => d.produto).take(limite).toList();
    }

    final scorePorProduto = <int, double>{};
    final scoreCliente = clienteId == null
        ? const <int, double>{}
        : _pontuacaoPorCliente(clienteId);

    for (final doc in _cacheDocs) {
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

    final resultados = _cacheDocs
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
    final ttlExpirado = _cacheMontadoEm == null ||
        agora.difference(_cacheMontadoEm!) > _cacheTtl;
    final estruturaMudou = produtoCount != _cacheProdutoCount;
    final historicoMudou =
        itemCount != _cacheItemCount || vendaCount != _cacheVendaCount;

    if (estruturaMudou || _cacheDocs.isEmpty || ttlExpirado) {
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

    if (consultaNormalizada == codigoBarras && codigoBarras.isNotEmpty) score += 1200;
    if (consultaNormalizada == codigoInterno && codigoInterno.isNotEmpty) score += 1000;
    if (nome.startsWith(consultaNormalizada)) score += 700;
    if (nome.contains(consultaNormalizada)) score += 450;
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
        final replace = prev[j - 1] +
            (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
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

  Iterable<String> _expandirTokensComSinonimos(List<String> tokens) sync* {
    const sinonimos = <String, List<String>>{
      'vergalhao': ['ferro', 'barra', 'aco'],
      'ferro': ['vergalhao', 'barra', 'aco'],
      'cx': ['caixa'],
      'caixa': ['cx'],
      'dagua': ['dagua', 'd agua', "d'agua"],
      'cimento': ['cp2', 'cpii', 'cp-2'],
      'cp2': ['cimento', 'cpii', 'cp-2'],
      'areia': ['fina', 'media', 'grossa'],
      'brita': ['pedra'],
    };
    for (final token in tokens) {
      yield token;
      final encontrados = sinonimos[token];
      if (encontrados != null) {
        for (final sin in encontrados) {
          yield _normalizarTexto(sin);
        }
      }
    }
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
    final id = _db.produtoBox.put(produto);
    _invalidarCacheBusca();
    return id;
  }

  bool remover(int id) {
    final ok = _db.produtoBox.remove(id);
    if (ok) {
      _invalidarCacheBusca();
    }
    return ok;
  }

  Produto? obterPorId(int id) => _db.produtoBox.get(id);

  void _invalidarCacheBusca() {
    _cacheDocs = const [];
    _cacheScoreHistorico = const {};
    _cacheScoreCliente.clear();
    _cacheProdutoCount = -1;
    _cacheItemCount = -1;
    _cacheVendaCount = -1;
    _cacheMontadoEm = null;
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

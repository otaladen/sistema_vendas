import 'package:http/http.dart' as http;

import '../config/preco_mercado_regiao_config.dart';
import '../data/objectbox.dart';
import '../domain/preco_mercado_estatistica.dart';
import '../domain/preco_mercado_resultado.dart';
import '../objectbox.g.dart';
import 'gemini_service.dart';
import 'trusted_http_client.dart';

class PrecoMercadoException implements Exception {
  PrecoMercadoException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => cause != null ? '$message ($cause)' : message;
}

/// Referencia de preco para Salvador/BA.
///
/// Sites grandes bloqueiam scraping (anti-bot). Por isso o fluxo principal e:
/// 1) limpar o nome do produto
/// 2) abrir atalhos no navegador (Ferreira Costa, Leroy, ML, Google Salvador)
/// 3) opcionalmente tentar Bing RSS por links
/// 4) calcular mediana com precos digitados pelo usuario + historico local
class PrecoMercadoService {
  PrecoMercadoService({
    http.Client? httpClient,
    GeminiService? geminiService,
    ObjectBox? objectBox,
    this.regiao = PrecoMercadoRegiaoConfig.atual,
  })  : _http = httpClient ?? createTrustedHttpClient(),
        _gemini = geminiService ?? GeminiService(),
        _db = objectBox;

  final http.Client _http;
  final GeminiService _gemini;
  final ObjectBox? _db;
  final PrecoMercadoRegiaoConfig regiao;

  static const Duration _timeout = Duration(seconds: 20);
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheTtl = Duration(hours: 6);

  static final _unidadesGenericas = {
    'UN',
    'UND',
    'PC',
    'PÇ',
    'PECA',
    'PEÇA',
  };

  /// Nome limpo para busca (nao acrescenta UN; remove unidade generica do fim).
  static String montarQueryBasica({
    required String nome,
    String codigoBarras = '',
    String unidade = '',
  }) {
    var nomeLimpo = nome.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (nomeLimpo.isEmpty) {
      final ean = codigoBarras.trim();
      return RegExp(r'^\d{8,14}$').hasMatch(ean) ? ean : '';
    }

    final u = unidade.trim().toUpperCase();
    if (u.isNotEmpty && _unidadesGenericas.contains(u)) {
      // Nao polui "CIMENTO 50KG POTY" com "UN".
    } else if (u.isNotEmpty &&
        !_unidadesGenericas.contains(u) &&
        !nomeLimpo.toUpperCase().contains(u)) {
      // So acrescenta unidade util (SC, CX, KG…) se ainda nao estiver no nome.
      if (!RegExp(
        r'\b' + RegExp.escape(u) + r'\b',
        caseSensitive: false,
      ).hasMatch(nomeLimpo)) {
        nomeLimpo = '$nomeLimpo $u';
      }
    }

    // Remove sufixo isolado UN/UND no fim do nome.
    nomeLimpo = nomeLimpo
        .replaceFirst(RegExp(r'\s+\b(UN|UND|PC)\b\s*$', caseSensitive: false), '')
        .trim();
    return nomeLimpo;
  }

  /// Atalhos de navegador — caminho que realmente funciona em Salvador.
  List<PrecoMercadoLinkExterno> montarLinksExternos(String termoProduto) {
    final termo = termoProduto.trim();
    if (termo.isEmpty) return const [];
    final q = Uri.encodeComponent(termo);
    final qSalvador = Uri.encodeComponent('$termo preco ${regiao.cidade} ${regiao.uf}');
    final slugMl = termo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9à-ü]+', caseSensitive: false), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return [
      PrecoMercadoLinkExterno(
        rotulo: 'Google Shopping · ${regiao.cidade}',
        loja: 'Google Shopping',
        url:
            'https://www.google.com/search?tbm=shop&q=${Uri.encodeComponent(termo)}'
            '&hl=pt-BR&gl=br&near=${Uri.encodeComponent('${regiao.cidade}, ${regiao.uf}')}',
      ),
      PrecoMercadoLinkExterno(
        rotulo: 'Google · ${regiao.cidade}',
        loja: 'Google',
        url: 'https://www.google.com/search?q=$qSalvador&hl=pt-BR&gl=br',
      ),
      PrecoMercadoLinkExterno(
        rotulo: 'Ferreira Costa',
        loja: 'Ferreira Costa',
        url:
            'https://www.google.com/search?q=${Uri.encodeComponent('$termo site:ferreiracosta.com ${regiao.cidade}')}&hl=pt-BR&gl=br',
      ),
      PrecoMercadoLinkExterno(
        rotulo: 'Leroy Merlin',
        loja: 'Leroy Merlin',
        url: 'https://www.leroymerlin.com.br/search?q=$q',
      ),
      PrecoMercadoLinkExterno(
        rotulo: 'Mercado Livre',
        loja: 'Mercado Livre',
        url: 'https://lista.mercadolivre.com.br/$slugMl',
      ),
    ];
  }

  /// Mantido para testes / compat.
  List<String> montarQueriesRegionais(
    String termoProduto, {
    String codigoBarras = '',
  }) {
    final base = termoProduto.trim();
    if (base.isEmpty) return const [];
    return [
      '$base ${regiao.cidade} preco',
      '$base Ferreira Costa',
      '$base Leroy Merlin',
      '$base Mercado Livre',
      if (RegExp(r'^\d{8,14}$').hasMatch(codigoBarras.trim()))
        '${codigoBarras.trim()} ${regiao.cidade}',
    ];
  }

  Future<PrecoMercadoResumo> buscar({
    required String nome,
    String codigoBarras = '',
    String unidade = '',
    int? produtoId,
    bool avancadaComGemini = false,
  }) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty && codigoBarras.trim().isEmpty) {
      throw PrecoMercadoException(
        'Informe o nome do produto (aba Principal) antes de buscar o preco.',
      );
    }

    var termo = montarQueryBasica(
      nome: nomeLimpo.isEmpty ? codigoBarras.trim() : nomeLimpo,
      codigoBarras: codigoBarras,
      unidade: unidade,
    );
    var dicaGemini = '';
    var queryAvancada = '';

    if (avancadaComGemini) {
      final avancado = await _gemini.sugerirQueryBuscaPreco(
        nomeLimpo.isEmpty ? codigoBarras.trim() : nomeLimpo,
        unidade: unidade,
        codigoBarras: codigoBarras,
        cidade: regiao.cidade,
        uf: regiao.uf,
        lojasAlvo: regiao.lojas.map((l) => l.nome).toList(),
      );
      if (avancado != null) {
        final q = avancado.queryBusca.trim();
        if (q.isNotEmpty) {
          queryAvancada = q;
          termo = montarQueryBasica(nome: q);
        }
        dicaGemini = avancado.dica.trim();
      }
    }

    final links = montarLinksExternos(termo);
    final cacheKey = 'v5|${regiao.cidade}|$termo';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.em) < _cacheTtl &&
        !avancadaComGemini) {
      return _enriquecerComHistoricoLocal(
        cached.resumo.copyWith(
          dicaGemini: dicaGemini,
          queryAvancadaUsada: queryAvancada,
          linksExternos: links,
        ),
        produtoId: produtoId,
      );
    }

    // Tentativa leve (muitos sites bloqueiam). Nao e o caminho principal.
    final auto = await _tentarColetaAutomatica(termo);
    final amostras = _priorizarAmostras(auto.amostras);
    final precos = amostras.map((a) => a.preco).toList();
    final filtrados = PrecoMercadoEstatistica.filtrarOutliers(precos);
    final preferidas = amostras.where((a) => a.prioritaria).toList();
    final filtradosPref =
        PrecoMercadoEstatistica.filtrarOutliers(preferidas.map((a) => a.preco));

    final usar = filtradosPref.length >= 2 ? filtradosPref : filtrados;
    final mediana = PrecoMercadoEstatistica.mediana(usar);
    final medianaPref = filtradosPref.length >= 2
        ? PrecoMercadoEstatistica.mediana(filtradosPref)
        : null;

    final aviso = usar.isEmpty
        ? 'Os sites bloqueiam coleta automatica. Abra as lojas de '
            '${regiao.cidade} abaixo, anote os precos e use "Calcular media".'
        : (filtradosPref.length < 2
            ? 'Poucas ofertas automaticas. Confira os links e complete os precos manualmente.'
            : '');

    final resumo = PrecoMercadoResumo(
      queryUsada: '$termo · ${regiao.rotulo}',
      amostras: amostras.take(12).toList(),
      precosFiltrados: usar,
      confianca: PrecoMercadoParser.confiancaDe(usar.length),
      fonte: PrecoMercadoFonte.mercadoWeb,
      mediana: mediana,
      medianaPrioritaria: medianaPref,
      p25: PrecoMercadoEstatistica.percentil(usar, 0.25),
      p75: PrecoMercadoEstatistica.percentil(usar, 0.75),
      minimo: PrecoMercadoEstatistica.minimo(usar),
      maximo: PrecoMercadoEstatistica.maximo(usar),
      aviso: aviso,
      queryAvancadaUsada: queryAvancada,
      dicaGemini: dicaGemini,
      regiaoLabel: regiao.rotulo,
      lojasPrioritarias: regiao.lojas.map((l) => l.nome).toList(),
      amostrasPrioritarias: filtradosPref.length,
      linksExternos: links,
      bloqueioAutomatico: auto.bloqueado || usar.isEmpty,
    );

    final finalResumo = _enriquecerComHistoricoLocal(
      resumo,
      produtoId: produtoId,
    );
    _cache[cacheKey] = _CacheEntry(DateTime.now(), finalResumo);
    return finalResumo;
  }

  /// Calcula mediana a partir de precos digitados (um por loja).
  PrecoMercadoResumo resumirPrecosManuais({
    required String queryUsada,
    required Map<String, double> precosPorLoja,
    PrecoMercadoResumo? base,
  }) {
    final amostras = <PrecoMercadoAmostra>[];
    precosPorLoja.forEach((loja, preco) {
      if (preco <= 0 || !preco.isFinite) return;
      amostras.add(
        PrecoMercadoAmostra(
          preco: preco,
          titulo: '$loja — informado',
          fonte: loja,
          prioritaria: regiao.lojas.any(
            (l) => l.nome.toLowerCase() == loja.toLowerCase(),
          ),
          regiaoHint: true,
        ),
      );
    });
    final filtrados =
        PrecoMercadoEstatistica.filtrarOutliers(amostras.map((a) => a.preco));
    final mediana = PrecoMercadoEstatistica.mediana(filtrados);
    return PrecoMercadoResumo(
      queryUsada: queryUsada,
      amostras: [
        ...amostras,
        ...?base?.amostras.where((a) => !a.titulo.contains('informado')),
      ],
      precosFiltrados: filtrados,
      confianca: PrecoMercadoParser.confiancaDe(filtrados.length),
      fonte: PrecoMercadoFonte.mercadoWeb,
      mediana: mediana,
      medianaPrioritaria: mediana,
      p25: PrecoMercadoEstatistica.percentil(filtrados, 0.25),
      p75: PrecoMercadoEstatistica.percentil(filtrados, 0.75),
      minimo: PrecoMercadoEstatistica.minimo(filtrados),
      maximo: PrecoMercadoEstatistica.maximo(filtrados),
      historicoLojaMediana: base?.historicoLojaMediana,
      historicoLojaAmostras: base?.historicoLojaAmostras ?? 0,
      aviso: filtrados.isEmpty
          ? 'Informe ao menos um preco das lojas de ${regiao.cidade}.'
          : 'Media calculada com os precos que voce informou (${regiao.rotulo}).',
      queryAvancadaUsada: base?.queryAvancadaUsada ?? '',
      dicaGemini: base?.dicaGemini ?? '',
      regiaoLabel: regiao.rotulo,
      lojasPrioritarias: regiao.lojas.map((l) => l.nome).toList(),
      amostrasPrioritarias: filtrados.length,
      linksExternos: base?.linksExternos ?? montarLinksExternos(queryUsada),
      bloqueioAutomatico: base?.bloqueioAutomatico ?? true,
    );
  }

  Future<_ColetaAuto> _tentarColetaAutomatica(String termo) async {
    final amostras = <PrecoMercadoAmostra>[];
    var bloqueado = false;

    try {
      final bing = await _buscarBingRss(termo);
      amostras.addAll(bing);
    } catch (_) {}

    try {
      final ddg = await _buscarDuckDuckGoUma(termo);
      if (ddg.bloqueado) {
        bloqueado = true;
      } else {
        amostras.addAll(ddg.amostras);
      }
    } catch (_) {
      bloqueado = true;
    }

    final porChave = <String, PrecoMercadoAmostra>{};
    for (final a in amostras) {
      final chave =
          '${a.url.isNotEmpty ? a.url : a.titulo}|${a.preco.toStringAsFixed(2)}';
      porChave.putIfAbsent(chave, () => a);
    }
    return _ColetaAuto(
      amostras: porChave.values.toList(),
      bloqueado: bloqueado && porChave.isEmpty,
    );
  }

  Future<List<PrecoMercadoAmostra>> _buscarBingRss(String termo) async {
    final uri = Uri.https('www.bing.com', '/search', {
      'format': 'rss',
      'q': '$termo preco ${regiao.cidade}',
      'setlang': 'pt-br',
      'cc': 'BR',
    });
    final response = await _http
        .get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'application/rss+xml, application/xml, text/xml, */*',
            'Accept-Language': 'pt-BR,pt;q=0.9',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) return const [];
    return _parseBingRss(response.body);
  }

  static List<PrecoMercadoAmostra> parseBingRssForTest(String xml) =>
      PrecoMercadoService._parseBingRssStatic(xml);

  List<PrecoMercadoAmostra> _parseBingRss(String xml) =>
      _parseBingRssStatic(xml);

  static List<PrecoMercadoAmostra> _parseBingRssStatic(String xml) {
    final out = <PrecoMercadoAmostra>[];
    final reItem = RegExp(
      r'<item>([\s\S]*?)</item>',
      caseSensitive: false,
    );
    for (final m in reItem.allMatches(xml)) {
      final block = m.group(1) ?? '';
      final title = _tagXml(block, 'title');
      final desc = _tagXml(block, 'description');
      final link = _tagXml(block, 'link');
      final texto = '$title. $desc';
      final preco = PrecoMercadoParser.extrairPrecoPrincipal(texto);
      if (preco == null) continue;
      if (preco < 0.5 || preco > 500000) continue;
      out.add(
        PrecoMercadoAmostra(
          preco: preco,
          titulo: title.isEmpty ? 'Oferta' : title,
          url: link,
          fonte: _rotuloFonte(link),
        ),
      );
    }
    return out;
  }

  static String _tagXml(String block, String tag) {
    final m = RegExp(
      '<$tag>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    if (m == null) return '';
    return _stripTags(_decodeHtml(m.group(1) ?? '')).trim();
  }

  Future<_ColetaAuto> _buscarDuckDuckGoUma(String query) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': '$query preco'});
    final response = await _http
        .get(
          uri,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.8',
          },
        )
        .timeout(_timeout);

    final body = response.body;
    if (response.statusCode == 202 ||
        body.contains('anomaly-modal') ||
        body.contains('bots use DuckDuckGo') ||
        body.contains('cc=botnet')) {
      return const _ColetaAuto(amostras: [], bloqueado: true);
    }
    if (response.statusCode != 200) {
      return const _ColetaAuto(amostras: [], bloqueado: true);
    }
    return _ColetaAuto(
      amostras: _parseHtmlDuckDuckGoStatic(body),
      bloqueado: false,
    );
  }

  static List<PrecoMercadoAmostra> parseHtmlDuckDuckGoForTest(String html) =>
      _parseHtmlDuckDuckGoStatic(html);

  static List<PrecoMercadoAmostra> _parseHtmlDuckDuckGoStatic(String html) {
    final out = <PrecoMercadoAmostra>[];
    final vistos = <String>{};

    void tentarAdd({
      required String titulo,
      required String textoPreco,
      required String url,
    }) {
      final preco = PrecoMercadoParser.extrairPrecoPrincipal(textoPreco);
      if (preco == null) return;
      if (preco < 0.5 || preco > 500000) return;
      final chave = '${url.isNotEmpty ? url : titulo}|${preco.toStringAsFixed(2)}';
      if (!vistos.add(chave)) return;
      out.add(
        PrecoMercadoAmostra(
          preco: preco,
          titulo: titulo.isEmpty ? 'Oferta' : titulo,
          url: url,
          fonte: _rotuloFonte(url),
        ),
      );
    }

    final reBloco = RegExp(
      r'class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>'
      r'[\s\S]*?class="result__snippet"[^>]*>(.*?)</a>',
      caseSensitive: false,
    );
    for (final m in reBloco.allMatches(html)) {
      final hrefRaw = _decodeHtml(m.group(1) ?? '');
      final titulo = _stripTags(_decodeHtml(m.group(2) ?? '')).trim();
      final snippet = _stripTags(_decodeHtml(m.group(3) ?? '')).trim();
      tentarAdd(
        titulo: titulo,
        textoPreco: '$titulo. $snippet',
        url: _extrairUrlFinal(hrefRaw),
      );
    }
    return out;
  }

  List<PrecoMercadoAmostra> _priorizarAmostras(
    List<PrecoMercadoAmostra> origem,
  ) {
    final cidade = regiao.cidade.toLowerCase();
    final uf = regiao.uf.toLowerCase();
    final enriquecidas = origem.map((a) {
      final prior = _lojaPrioritariaDe(a.url, a.titulo, a.fonte);
      final texto = '${a.titulo} ${a.fonte}'.toLowerCase();
      final hint = texto.contains(cidade) ||
          texto.contains(' $uf') ||
          texto.contains('-$uf') ||
          texto.contains('/$uf');
      final fonte = prior?.nome ??
          (_rotuloFonte(a.url).isEmpty ? a.fonte : _rotuloFonte(a.url));
      return PrecoMercadoAmostra(
        preco: a.preco,
        titulo: a.titulo,
        url: a.url,
        fonte: fonte,
        prioritaria: prior != null,
        regiaoHint: hint,
      );
    }).toList();

    enriquecidas.sort((a, b) {
      final pa = (a.prioritaria ? 4 : 0) + (a.regiaoHint ? 1 : 0);
      final pb = (b.prioritaria ? 4 : 0) + (b.regiaoHint ? 1 : 0);
      final cmp = pb.compareTo(pa);
      if (cmp != 0) return cmp;
      return a.preco.compareTo(b.preco);
    });
    return enriquecidas;
  }

  PrecoMercadoLojaAlvo? _lojaPrioritariaDe(
    String url,
    String titulo,
    String fonte,
  ) {
    final blob = '$url $titulo $fonte'.toLowerCase();
    for (final loja in regiao.lojas) {
      if (loja.correspondeUrl(url)) return loja;
      if (blob.contains(loja.nome.toLowerCase())) return loja;
      for (final t in loja.termosSite) {
        if (blob.contains(t.toLowerCase())) return loja;
      }
    }
    return null;
  }

  PrecoMercadoResumo _enriquecerComHistoricoLocal(
    PrecoMercadoResumo base, {
    int? produtoId,
  }) {
    final db = _db;
    if (db == null || produtoId == null || produtoId <= 0) return base;

    final fim = DateTime.now();
    final inicio = fim.subtract(const Duration(days: 180));
    final qb = db.itemVendaBox.query(ItemVenda_.produto.equals(produtoId));
    qb.link(
      ItemVenda_.venda,
      Venda_.status
          .equals('finalizada')
          .and(Venda_.cancelada.equals(false))
          .and(Venda_.data.greaterOrEqualDate(inicio.toUtc()))
          .and(Venda_.data.lessOrEqualDate(fim.toUtc())),
    );
    final q = qb.build();
    try {
      final itens = q.find();
      final precos = <double>[];
      for (final item in itens) {
        final qtd = item.quantidade - item.quantidadeDevolvida;
        if (qtd <= 0) continue;
        if (item.precoUnitario > 0) precos.add(item.precoUnitario);
      }
      final filtrados = PrecoMercadoEstatistica.filtrarOutliers(precos);
      final medianaLoja = PrecoMercadoEstatistica.mediana(filtrados);
      final fonte = base.temMercado
          ? (medianaLoja != null
              ? PrecoMercadoFonte.mista
              : PrecoMercadoFonte.mercadoWeb)
          : (medianaLoja != null
              ? PrecoMercadoFonte.lojaLocal
              : base.fonte);

      var aviso = base.aviso;
      if (!base.temMercado && medianaLoja != null) {
        aviso =
            'Sem oferta web automatica em ${regiao.rotulo}. '
            'Histor historico da loja e use os links para completar.';
      }

      return base.copyWith(
        historicoLojaMediana: medianaLoja,
        historicoLojaAmostras: filtrados.length,
        fonte: fonte,
        aviso: aviso,
      );
    } finally {
      q.close();
    }
  }

  static String _extrairUrlFinal(String href) {
    final h = href.trim();
    if (h.isEmpty) return '';
    final uddg = RegExp(
      r'[?&]uddg=([^&]+)',
      caseSensitive: false,
    ).firstMatch(h);
    if (uddg != null) {
      try {
        return Uri.decodeComponent(uddg.group(1)!);
      } catch (_) {}
    }
    if (h.startsWith('//')) return 'https:$h';
    if (h.startsWith('http')) return h;
    return '';
  }

  static String _rotuloFonte(String url) {
    final u = url.toLowerCase();
    if (u.contains('ferreiracosta')) return 'Ferreira Costa';
    if (u.contains('mercadolivre')) return 'Mercado Livre';
    if (u.contains('leroymerlin')) return 'Leroy Merlin';
    if (u.contains('magazineluiza') || u.contains('magalu')) return 'Magalu';
    if (u.contains('amazon.')) return 'Amazon';
    if (u.isEmpty) return 'Web';
    try {
      return Uri.parse(u).host.replaceFirst('www.', '');
    } catch (_) {
      return 'Web';
    }
  }

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ');

  static String _decodeHtml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }
}

class _ColetaAuto {
  const _ColetaAuto({required this.amostras, required this.bloqueado});
  final List<PrecoMercadoAmostra> amostras;
  final bool bloqueado;
}

class _CacheEntry {
  _CacheEntry(this.em, this.resumo);
  final DateTime em;
  final PrecoMercadoResumo resumo;
}

extension on PrecoMercadoResumo {
  PrecoMercadoResumo copyWith({
    String? queryUsada,
    List<PrecoMercadoAmostra>? amostras,
    List<double>? precosFiltrados,
    PrecoMercadoConfianca? confianca,
    PrecoMercadoFonte? fonte,
    double? mediana,
    double? p25,
    double? p75,
    double? minimo,
    double? maximo,
    double? historicoLojaMediana,
    int? historicoLojaAmostras,
    String? aviso,
    String? queryAvancadaUsada,
    String? dicaGemini,
    String? regiaoLabel,
    List<String>? lojasPrioritarias,
    int? amostrasPrioritarias,
    double? medianaPrioritaria,
    List<PrecoMercadoLinkExterno>? linksExternos,
    bool? bloqueioAutomatico,
  }) {
    return PrecoMercadoResumo(
      queryUsada: queryUsada ?? this.queryUsada,
      amostras: amostras ?? this.amostras,
      precosFiltrados: precosFiltrados ?? this.precosFiltrados,
      confianca: confianca ?? this.confianca,
      fonte: fonte ?? this.fonte,
      mediana: mediana ?? this.mediana,
      p25: p25 ?? this.p25,
      p75: p75 ?? this.p75,
      minimo: minimo ?? this.minimo,
      maximo: maximo ?? this.maximo,
      historicoLojaMediana: historicoLojaMediana ?? this.historicoLojaMediana,
      historicoLojaAmostras:
          historicoLojaAmostras ?? this.historicoLojaAmostras,
      aviso: aviso ?? this.aviso,
      queryAvancadaUsada: queryAvancadaUsada ?? this.queryAvancadaUsada,
      dicaGemini: dicaGemini ?? this.dicaGemini,
      regiaoLabel: regiaoLabel ?? this.regiaoLabel,
      lojasPrioritarias: lojasPrioritarias ?? this.lojasPrioritarias,
      amostrasPrioritarias:
          amostrasPrioritarias ?? this.amostrasPrioritarias,
      medianaPrioritaria: medianaPrioritaria ?? this.medianaPrioritaria,
      linksExternos: linksExternos ?? this.linksExternos,
      bloqueioAutomatico: bloqueioAutomatico ?? this.bloqueioAutomatico,
    );
  }
}

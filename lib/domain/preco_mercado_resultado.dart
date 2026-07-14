enum PrecoMercadoConfianca { baixa, media, alta }

enum PrecoMercadoFonte { mercadoWeb, lojaLocal, mista }

/// Uma oferta/amostra encontrada na web ou no historico local.
class PrecoMercadoAmostra {
  const PrecoMercadoAmostra({
    required this.preco,
    required this.titulo,
    this.url = '',
    this.fonte = 'web',
    this.prioritaria = false,
    this.regiaoHint = false,
  });

  final double preco;
  final String titulo;
  final String url;
  final String fonte;
  /// True se veio de Ferreira Costa / Leroy / ML (lojas-alvo).
  final bool prioritaria;
  /// True se o snippet/titulo cita a cidade/UF da regiao.
  final bool regiaoHint;
}

/// Atalho para abrir a busca no navegador (lojas de Salvador).
class PrecoMercadoLinkExterno {
  const PrecoMercadoLinkExterno({
    required this.rotulo,
    required this.url,
    this.loja = '',
  });

  final String rotulo;
  final String url;
  final String loja;
}

class PrecoMercadoResumo {
  const PrecoMercadoResumo({
    required this.queryUsada,
    required this.amostras,
    required this.precosFiltrados,
    required this.confianca,
    required this.fonte,
    this.mediana,
    this.p25,
    this.p75,
    this.minimo,
    this.maximo,
    this.historicoLojaMediana,
    this.historicoLojaAmostras = 0,
    this.aviso = '',
    this.queryAvancadaUsada = '',
    this.dicaGemini = '',
    this.regiaoLabel = '',
    this.lojasPrioritarias = const [],
    this.amostrasPrioritarias = 0,
    this.medianaPrioritaria,
    this.linksExternos = const [],
    this.bloqueioAutomatico = false,
  });

  final String queryUsada;
  final List<PrecoMercadoAmostra> amostras;
  final List<double> precosFiltrados;
  final PrecoMercadoConfianca confianca;
  final PrecoMercadoFonte fonte;
  final double? mediana;
  final double? p25;
  final double? p75;
  final double? minimo;
  final double? maximo;
  final double? historicoLojaMediana;
  final int historicoLojaAmostras;
  final String aviso;
  final String queryAvancadaUsada;
  final String dicaGemini;
  final String regiaoLabel;
  final List<String> lojasPrioritarias;
  final int amostrasPrioritarias;
  /// Mediana so das lojas-alvo (quando houver amostra suficiente).
  final double? medianaPrioritaria;
  final List<PrecoMercadoLinkExterno> linksExternos;
  /// True quando a web bloqueou scraping (anti-bot).
  final bool bloqueioAutomatico;

  bool get temMercado => mediana != null && precosFiltrados.isNotEmpty;

  /// Preco sugerido: prioriza mediana das lojas locais/alvo.
  double? get precoSugerido => medianaPrioritaria ?? mediana;
}

/// Extracao de valores monetarios em textos de busca (snippets BR).
class PrecoMercadoParser {
  PrecoMercadoParser._();

  /// Captura R$ 47,90 | R$47,90 | R$ 1.234,56 | R$ 47 90 | R$ 47.
  static final RegExp _rePreco = RegExp(
    r'(?:R\s*\$|R\$)\s*(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d{1,5}\s+\d{2}|\d{1,5}(?:[.,]\d{2})?)',
    caseSensitive: false,
  );

  static final RegExp _rePorUnidade = RegExp(
    r'pre[cç]o\s+por\s+(quilo|kg|metro|m2|m²|litro)|/\s*kg|por\s+kg',
    caseSensitive: false,
  );

  /// Extrai o melhor preco candidato de [texto] (prioriza valor principal).
  static double? extrairPrecoPrincipal(String texto) {
    final limpo = texto
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final matches = _rePreco.allMatches(limpo).toList();
    if (matches.isEmpty) return null;

    double? principal;
    double? porUnidade;
    for (final m in matches) {
      final valor = parseBrl(m.group(1) ?? '');
      if (valor == null || valor <= 0) continue;
      final inicio = m.start;
      final contexto = limpo
          .substring(
            (inicio - 48).clamp(0, limpo.length),
            (m.end + 16).clamp(0, limpo.length),
          )
          .toLowerCase();
      if (_rePorUnidade.hasMatch(contexto)) {
        porUnidade ??= valor;
        continue;
      }
      // Prefere o primeiro preco "de embalagem"; ignora valores de frete tipicos baixos
      // so quando ja temos um principal e o novo e muito menor.
      if (principal == null) {
        principal = valor;
      } else if (valor >= principal * 0.4 && valor <= principal * 3) {
        // mantem o primeiro razoavel da faixa
      }
    }
    return principal ?? porUnidade;
  }

  static double? parseBrl(String bruto) {
    var s = bruto.trim();
    if (s.isEmpty) return null;

    // "47 90" (espaco = centavos) → 47.90
    final espacoCentavos = RegExp(r'^(\d{1,5})\s+(\d{2})$').firstMatch(s);
    if (espacoCentavos != null) {
      final reais = int.tryParse(espacoCentavos.group(1)!);
      final cents = int.tryParse(espacoCentavos.group(2)!);
      if (reais == null || cents == null) return null;
      return reais + cents / 100.0;
    }

    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d+\.\d{2}$').hasMatch(s)) {
      // 32.90 estilo internacional
    }
    return double.tryParse(s);
  }

  static PrecoMercadoConfianca confiancaDe(int amostrasValidas) {
    if (amostrasValidas >= 5) return PrecoMercadoConfianca.alta;
    if (amostrasValidas >= 2) return PrecoMercadoConfianca.media;
    return PrecoMercadoConfianca.baixa;
  }

  /// Extrai todos os precos R$ de um texto colado (para preencher campos).
  static List<double> extrairTodosPrecos(String texto) {
    final limpo = texto
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final out = <double>[];
    for (final m in _rePreco.allMatches(limpo)) {
      final valor = parseBrl(m.group(1) ?? '');
      if (valor == null || valor <= 0 || valor > 500000) continue;
      final inicio = m.start;
      final contexto = limpo
          .substring(
            (inicio - 48).clamp(0, limpo.length),
            (m.end + 16).clamp(0, limpo.length),
          )
          .toLowerCase();
      if (_rePorUnidade.hasMatch(contexto)) continue;
      out.add(valor);
    }
    return out;
  }

  /// Tenta mapear precos colados por nome de loja no texto.
  static Map<String, double> extrairPrecosPorLoja(String texto) {
    final lower = texto.toLowerCase();
    final mapa = <String, double>{};
    void tentar(String chave, List<String> aliases) {
      for (final a in aliases) {
        final idx = lower.indexOf(a);
        if (idx < 0) continue;
        final janela = texto.substring(
          idx,
          (idx + a.length + 80).clamp(0, texto.length),
        );
        final preco = extrairPrecoPrincipal(janela);
        if (preco != null) {
          mapa[chave] = preco;
          return;
        }
      }
    }

    tentar('Ferreira Costa', ['ferreira costa', 'ferreiracosta', 'f. costa']);
    tentar('Leroy Merlin', ['leroy merlin', 'leroymerlin', 'leroy']);
    tentar('Mercado Livre', ['mercado livre', 'mercadolivre', 'meli']);
    return mapa;
  }
}

/// Query sugerida pelo Gemini (sem precos inventados).
class PrecoMercadoQueryAvancada {
  const PrecoMercadoQueryAvancada({
    required this.queryBusca,
    this.dica = '',
  });

  final String queryBusca;
  final String dica;

  factory PrecoMercadoQueryAvancada.fromMap(Map<String, dynamic> map) {
    return PrecoMercadoQueryAvancada(
      queryBusca: (map['query_busca'] ?? '').toString(),
      dica: (map['dica'] ?? '').toString(),
    );
  }
}

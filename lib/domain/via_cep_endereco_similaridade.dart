import '../services/viacep_endereco_service.dart';

/// Normaliza texto para comparacao (minusculas, sem acentos, espacos simples).
String normalizarTextoEndereco(String value) {
  const mapa = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
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
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  final buf = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buf.write(mapa[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Remove numero, complemento e tipo de logradouro para consulta na ViaCEP.
String extrairLogradouroParaBuscaCep(String endereco) {
  var s = endereco.trim();
  s = s.replaceFirst(
    RegExp(r'\s+n[º°o\.]?\s*\d+.*$', caseSensitive: false),
    '',
  );
  s = s.replaceFirst(RegExp(r'\s*,\s*\d+.*$'), '');
  s = s.replaceFirst(RegExp(r'\s+\d+\s*[-–]?\s*\w*$'), '');
  s = s.replaceFirst(
    RegExp(
      r'^(rua|r\.|av\.?|avenida|trav\.?|travessa|alameda|rod\.?|rodovia|'
      r'estrada|praca|largo|via|viela|bc\.?|beco)\s+',
      caseSensitive: false,
    ),
    '',
  );
  return s.trim();
}

/// Termos do mais especifico ao mais amplo para tentativas na ViaCEP.
List<String> termosBuscaLogradouroViaCep(String endereco) {
  final raw = endereco.trim();
  final out = <String>[];

  void add(String s) {
    final t = s.trim();
    if (t.length < 3) return;
    if (!out.any((e) => e.toLowerCase() == t.toLowerCase())) {
      out.add(t);
    }
  }

  final semNumero = extrairLogradouroParaBuscaCep(raw);
  add(semNumero);
  add(raw);

  final norm = normalizarTextoEndereco(semNumero.isNotEmpty ? semNumero : raw);
  final palavras = norm.split(' ').where((p) => p.length >= 3).toList();
  if (palavras.length >= 2) {
    add(palavras.join(' '));
  }
  if (palavras.length >= 3) {
    add(palavras.sublist(0, palavras.length - 1).join(' '));
  }
  if (palavras.isNotEmpty) {
    add(palavras.first);
  }

  return out;
}

int pontuarSimilaridadeEnderecoViaCep({
  required String logradouroReferencia,
  required String bairroReferencia,
  required ViaCepEnderecoResultado resultado,
}) {
  final refLog = normalizarTextoEndereco(logradouroReferencia);
  final refBairro = normalizarTextoEndereco(bairroReferencia);
  final resLog = normalizarTextoEndereco(resultado.logradouro);
  final resBairro = normalizarTextoEndereco(resultado.bairro);
  final refSemTipo = normalizarTextoEndereco(
    extrairLogradouroParaBuscaCep(logradouroReferencia),
  );

  var score = 0;

  if (refLog.isNotEmpty && resLog == refLog) score += 200;
  if (refSemTipo.isNotEmpty && resLog == refSemTipo) score += 180;
  if (refLog.isNotEmpty && (resLog.contains(refLog) || refLog.contains(resLog))) {
    score += 120;
  }
  if (refSemTipo.isNotEmpty &&
      refSemTipo.length >= 3 &&
      (resLog.contains(refSemTipo) || refSemTipo.contains(resLog))) {
    score += 100;
  }

  final tokensRef = {
    ...refLog.split(' '),
    ...refSemTipo.split(' '),
  }.where((t) => t.length >= 3);
  for (final token in tokensRef) {
    if (resLog.contains(token)) score += 15;
    if (resBairro.contains(token)) score += 5;
  }

  if (refBairro.length >= 2) {
    if (resBairro == refBairro) {
      score += 80;
    } else if (resBairro.contains(refBairro) || refBairro.contains(resBairro)) {
      score += 40;
    }
  }

  return score;
}

/// Ordena do mais parecido ao menos; descarta itens muito distantes quando houver melhores.
List<ViaCepEnderecoResultado> ordenarEnderecosPorSimilaridade({
  required List<ViaCepEnderecoResultado> lista,
  required String logradouroReferencia,
  String bairroReferencia = '',
  int limite = 50,
}) {
  if (lista.isEmpty) return lista;

  final pontuados = lista
      .map(
        (r) => (
          r,
          pontuarSimilaridadeEnderecoViaCep(
            logradouroReferencia: logradouroReferencia,
            bairroReferencia: bairroReferencia,
            resultado: r,
          ),
        ),
      )
      .toList()
    ..sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      if (cmp != 0) return cmp;
      return a.$1.logradouro.compareTo(b.$1.logradouro);
    });

  const minScoreUtil = 20;
  final fortes = pontuados.where((e) => e.$2 >= minScoreUtil).map((e) => e.$1);
  final base = fortes.isNotEmpty ? fortes : pontuados.map((e) => e.$1);
  return base.take(limite).toList();
}

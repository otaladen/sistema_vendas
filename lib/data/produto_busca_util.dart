/// Utilitarios compartilhados do motor de busca de produtos (PDV, cadastro, estoque).
library;

import '../model/produto.dart';

/// SKU reservado ao ERP (ex.: frete retirada futura). Nao vende no balcao.
const String kCodigoInternoFreteRetiradaFutura = '__FRETE_RET_FUTURA__';

/// Diferenca da troca enviada ao caixa (servico, sem baixa de estoque).
const String kCodigoInternoComplementoTroca = '__COMPLEMENTO_TROCA__';

/// Produto criado pelo sistema (codigo interno com prefixo `__`).
bool produtoEhCadastroInternoSistema(Produto produto) {
  final codigo = produto.codigoInterno.trim();
  return codigo.startsWith('__') && codigo.endsWith('__');
}

/// Sinônimos de medidas/abreviacoes de obra (chaves ja normalizadas).
const Map<String, List<String>> kProdutoBuscaMedidasSinonimos = {
  'pol': ['polegada', 'polegadas', 'pol.'],
  'polegada': ['pol', 'polegadas'],
  'polegadas': ['pol', 'polegada'],
  'mm': ['milimetro', 'milimetros'],
  'milimetro': ['mm', 'milimetros'],
  'milimetros': ['mm', 'milimetro'],
  'cm': ['centimetro', 'centimetros'],
  'centimetro': ['cm', 'centimetros'],
  'm': ['metro', 'metros', 'metragem'],
  'metro': ['m', 'metros', 'metragem'],
  'm2': ['metro quadrado', 'metros quadrados', 'mq'],
  'mq': ['m2', 'metro quadrado'],
  'm3': ['metro cubico', 'metros cubicos'],
  'kg': ['quilo', 'quilograma', 'quilos'],
  'g': ['grama', 'gramas'],
  'l': ['litro', 'litros', 'lt'],
  'lt': ['l', 'litro', 'litros'],
  'gal': ['galao', 'galoes'],
  'galao': ['gal', 'galoes'],
};

/// Remove tudo que nao for digito (GTIN / SKU numerico).
String somenteDigitosBusca(String texto) =>
    texto.replaceAll(RegExp(r'\D'), '');

/// Texto e somente digitos (ignora espacos).
bool textoSomenteDigitosBusca(String texto) {
  final t = texto.trim().replaceAll(RegExp(r'\s'), '');
  return t.isNotEmpty && RegExp(r'^\d+$').hasMatch(t);
}

/// SKU numerico sem zeros a esquerda (008858 -> 8858). Null se nao for so digitos.
String? skuNumericoSemZerosEsquerda(String texto) {
  if (!textoSomenteDigitosBusca(texto)) return null;
  final digits = somenteDigitosBusca(texto);
  if (digits.isEmpty) return null;
  final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
  return stripped.isEmpty ? '0' : stripped;
}

/// SKU composto so por digitos (8858, 12). Ignora SKU-, NFE-, __...__.
bool skuEhNumericoSequencial(String codigoInterno) {
  final t = codigoInterno.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (lower.startsWith('__') && lower.endsWith('__')) return false;
  return textoSomenteDigitosBusca(t);
}

/// SKU curto de balcao (1..9999999). Exclui EAN/GTIN usados por engano como SKU.
bool skuEhNumericoSequencialCurto(String codigoInterno) {
  if (!skuEhNumericoSequencial(codigoInterno)) return false;
  final digits = somenteDigitosBusca(codigoInterno);
  return digits.isNotEmpty && digits.length <= 7;
}

/// Parece codigo de barras (EAN/UPC/GTIN) — inadequado como SKU de loja.
bool skuPareceCodigoBarrasGtin(String codigo) {
  final t = codigo.trim();
  if (t.isEmpty || !textoSomenteDigitosBusca(t)) return false;
  final digits = somenteDigitosBusca(t);
  if (digits.length >= 8) return true;
  return false;
}

/// Valor inteiro de SKU numerico puro; null se alfanumerico ou reservado.
int? skuComoInteiroSequencial(String codigoInterno) {
  if (!skuEhNumericoSequencial(codigoInterno)) return null;
  return int.tryParse(somenteDigitosBusca(codigoInterno));
}

/// Proximo SKU numerico curto (1, 2, 3...) com base no maior ja usado.
/// Ignora GTINs longos indevidamente gravados em [codigoInterno].
String proximoSkuNumericoSequencial(Iterable<String> codigosExistentes) {
  var maxN = 0;
  final ocupados = <String>{};
  for (final raw in codigosExistentes) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final canon = normalizarCodigoInternoPersistido(t).toLowerCase();
    if (canon.isNotEmpty) ocupados.add(canon);
    if (!skuEhNumericoSequencialCurto(t)) continue;
    final n = skuComoInteiroSequencial(t);
    if (n != null && n > maxN) maxN = n;
  }
  var candidato = maxN + 1;
  while (ocupados.contains('$candidato')) {
    candidato++;
  }
  return '$candidato';
}

/// SKU canonico para gravacao: remove zeros a esquerda em codigos so numericos.
/// Codigos internos do sistema (`__...__`) e alfanumericos permanecem inalterados.
String normalizarCodigoInternoPersistido(String codigo) {
  final t = codigo.trim();
  if (t.isEmpty) return t;
  final lower = t.toLowerCase();
  if (lower.startsWith('__') && lower.endsWith('__')) return t;
  final canon = skuNumericoSemZerosEsquerda(t);
  return canon ?? t;
}

/// Match exato de codigo interno: literal ou numerico sem zeros a esquerda.
bool skuBuscaCorrespondeExato(String consulta, String codigoInterno) {
  final c = consulta.trim().toLowerCase();
  final sku = codigoInterno.trim().toLowerCase();
  if (c.isEmpty || sku.isEmpty) return false;
  if (c == sku) return true;
  final cNum = skuNumericoSemZerosEsquerda(c);
  final sNum = skuNumericoSemZerosEsquerda(sku);
  if (cNum != null && sNum != null && cNum == sNum) return true;
  return false;
}

/// Pontos extras quando a consulta e prefixo/sufixo de SKU numerico (885 -> 008858).
int? skuBuscaPontuacaoParcial(String consulta, String codigoInterno) {
  final cNum = skuNumericoSemZerosEsquerda(consulta);
  final sNum = skuNumericoSemZerosEsquerda(codigoInterno);
  if (cNum == null || sNum == null || cNum.isEmpty) return null;
  if (cNum == sNum) return 1000;
  if (sNum.startsWith(cNum)) return 880;
  if (cNum.length >= 3 && sNum.endsWith(cNum)) return 720;
  return null;
}

/// Consulta tipica de leitor (8 a 14 digitos, opcionalmente com espacos).
bool consultaPareceCodigoBarras(String termo) {
  final dig = somenteDigitosBusca(termo.trim());
  return dig.length >= 8 && dig.length <= 14;
}

/// Entrada provavelmente completa de leitor (so digitos, tamanho GTIN usual).
bool consultaEanProvavelCompleto(String termo) {
  final bruto = termo.trim();
  if (bruto.isEmpty) return false;
  final semEspaco = bruto.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d+$').hasMatch(semEspaco)) return false;
  final dig = somenteDigitosBusca(bruto);
  return dig.length >= 8 && dig.length <= 14;
}

/// Normaliza GTIN para comparacao (somente digitos; preserva zeros a esquerda).
String normalizarCodigoBarrasConsulta(String termo) =>
    somenteDigitosBusca(termo.trim());

/// Separa apelidos e codigos alternativos cadastrados (; , ou quebra de linha).
List<String> parseApelidosBusca(String raw) {
  final texto = raw.trim();
  if (texto.isEmpty) return const [];
  final partes = texto.split(RegExp(r'[;\n,]+'));
  final out = <String>[];
  final vistos = <String>{};
  for (final parte in partes) {
    final p = parte.trim();
    if (p.isEmpty) continue;
    final chave = p.toLowerCase();
    if (vistos.add(chave)) out.add(p);
  }
  return out;
}

/// Codigos somente-digitos (EAN alternativos) extraidos dos apelidos.
List<String> codigosBarrasAlternativosDeApelidos(Iterable<String> apelidos) {
  final out = <String>[];
  final vistos = <String>{};
  for (final a in apelidos) {
    final dig = somenteDigitosBusca(a);
    if (dig.length < 8 || dig.length > 14) continue;
    if (vistos.add(dig)) out.add(dig);
  }
  return out;
}

/// Tokens de medidas/dimensoes extraidos do texto do produto (ja normalizado).
List<String> extrairTokensMedidasDeTexto(String textoNormalizado) {
  if (textoNormalizado.isEmpty) return const [];
  final tokens = <String>{};

  void add(String t) {
    final x = t.trim();
    if (x.isNotEmpty) tokens.add(x);
  }

  // Fracoes: 3/4, 1.1/2, 1-1/2
  for (final m in RegExp(
    r'\b\d+(?:[.,]\d+)?/\d+\b|\b\d+-\d+/\d+\b',
  ).allMatches(textoNormalizado)) {
    add(m.group(0)!);
    final partes = m.group(0)!.split('/');
    if (partes.length == 2) {
      add(partes[0]);
      add(partes[1]);
    }
  }

  // Dimensoes 2,44x1,22 ou 2.44 x 1.22
  for (final m in RegExp(
    r'\b\d+(?:[.,]\d+)?\s*x\s*\d+(?:[.,]\d+)?\b',
  ).allMatches(textoNormalizado)) {
    final bloco = m.group(0)!;
    add(bloco.replaceAll(' ', ''));
    for (final n in RegExp(r'\d+(?:[.,]\d+)?').allMatches(bloco)) {
      add(n.group(0)!);
    }
  }

  // Numero + unidade: 50mm, 3 pol, 10kg
  for (final m in RegExp(
    r'\b\d+(?:[.,]\d+)?\s*(?:mm|cm|m2|m3|mq|kg|g|lt|l|pol|polegadas?)\b',
  ).allMatches(textoNormalizado)) {
    add(m.group(0)!);
    final num = RegExp(r'^\d+(?:[.,]\d+)?').firstMatch(m.group(0)!);
    if (num != null) add(num.group(0)!);
    final un = RegExp(
      r'(mm|cm|m2|m3|mq|kg|g|lt|l|pol|polegadas?)$',
    ).firstMatch(m.group(0)!);
    if (un != null) add(un.group(1)!);
  }

  // Numeros isolados 2-4 digitos (diametro/bitola comum em obra)
  for (final m in RegExp(r'\b\d{2,4}\b').allMatches(textoNormalizado)) {
    add(m.group(0)!);
  }

  return tokens.toList();
}

/// Expande tokens da consulta com sinonimos de medidas.
Iterable<String> expandirTokensMedidasObra(List<String> tokens) sync* {
  for (final token in tokens) {
    if (token.isEmpty) continue;
    yield token;
    final encontrados = kProdutoBuscaMedidasSinonimos[token];
    if (encontrados != null) {
      for (final sin in encontrados) {
        if (sin.isNotEmpty) yield sin;
      }
    }
  }
}

/// Remove espacos para comparar dimensoes (ex.: `1 1/2x13` == `11/2x13`).
String compactarTextoBuscaObra(String texto) =>
    texto.replaceAll(RegExp(r'\s+'), '');

/// Blocos de medida na consulta: `1 1/2x13`, `21/2x10`, `15x18`.
final RegExp _reBlocoMedidaConsulta = RegExp(
  r'\d+\s+\d+/\d+x\d+|\d+/\d+x\d+|\d+(?:[.,]\d+)?\s*x\s*\d+(?:[.,]\d+)?',
);

/// Resultado da tokenizacao inteligente da consulta (obra / ferragens).
class ConsultaObraParse {
  const ConsultaObraParse({
    required this.tokensSignificativos,
    required this.frases,
    required this.consultaCompacta,
  });

  /// Tokens que definem a intencao (sem `1` solto entre `21`, etc.).
  final List<String> tokensSignificativos;

  /// Frases/blocos para match quase-exato no nome.
  final List<String> frases;

  final String consultaCompacta;
}

/// Agrupa fracao mista + bitola (`prego 1 1/2x13` -> prego, 1 1/2x13, 11/2x13).
ConsultaObraParse tokenizarConsultaObra(String textoNormalizado) {
  final consulta = textoNormalizado.trim();
  if (consulta.isEmpty) {
    return const ConsultaObraParse(
      tokensSignificativos: [],
      frases: [],
      consultaCompacta: '',
    );
  }

  final frases = <String>{consulta};
  final significativos = <String>{};
  var restante = consulta;

  for (final m in _reBlocoMedidaConsulta.allMatches(consulta)) {
    final bruto = m.group(0)!.trim();
    final normalizado = bruto.replaceAll(RegExp(r'\s+'), ' ');
    frases.add(normalizado);
    frases.add(compactarTextoBuscaObra(normalizado));
    significativos.add(normalizado);
    significativos.add(compactarTextoBuscaObra(normalizado));
    restante = restante.replaceAll(m.group(0)!, ' ');
  }

  final partesRestantes = <String>[];
  for (final parte in restante.split(RegExp(r'\s+'))) {
    final p = parte.trim();
    if (p.isEmpty) continue;
    // So ignora digito isolado (evita `1` em `21`); bitolas 25, 50, 100 permanecem.
    if (p.length == 1 && RegExp(r'^\d$').hasMatch(p)) continue;
    partesRestantes.add(p);
    significativos.add(p);
    frases.add(p);
  }

  // Frases de multiplas palavras: "tubo 25", "cimento cp2".
  for (var i = 0; i < partesRestantes.length - 1; i++) {
    final bi = '${partesRestantes[i]} ${partesRestantes[i + 1]}';
    frases.add(bi);
    frases.add(compactarTextoBuscaObra(bi));
    if (i + 2 < partesRestantes.length) {
      final tri = '${partesRestantes[i]} ${partesRestantes[i + 1]} '
          '${partesRestantes[i + 2]}';
      frases.add(tri);
    }
  }

  final compacta = compactarTextoBuscaObra(consulta);
  frases.add(compacta);

  return ConsultaObraParse(
    tokensSignificativos: significativos.toList(),
    frases: frases.where((f) => f.length >= 2).toList(),
    consultaCompacta: compacta,
  );
}

/// Tokens aparecem no texto na mesma ordem (ex.: tubo ... 25).
bool sequenciaTokensNoTexto(String texto, List<String> tokens) {
  if (texto.isEmpty || tokens.isEmpty) return false;
  var pos = 0;
  for (final token in tokens) {
    if (token.isEmpty) continue;
    final avanco = _avancarAposTokenObra(texto, token, pos);
    if (avanco < 0) return false;
    pos = avanco;
  }
  return true;
}

/// Retorna a posicao apos o token, ou -1 se nao encontrado a partir de [inicio].
int _avancarAposTokenObra(String texto, String token, int inicio) {
  if (inicio > texto.length) return -1;
  final sub = texto.substring(inicio);
  if (!textoContemTokenObra(sub, token)) return -1;

  if (RegExp(r'^\d+$').hasMatch(token)) {
    final re = RegExp(r'(^|\s)' + RegExp.escape(token) + r'(\s|$|/)');
    final m = re.firstMatch(sub);
    if (m != null) {
      return inicio + m.end;
    }
    final idx = sub.indexOf(token);
    return idx < 0 ? -1 : inicio + idx + token.length;
  }

  final re = RegExp(r'(^|\s)' + RegExp.escape(token) + r'($|\s)');
  final m = re.firstMatch(sub);
  if (m != null) {
    return inicio + m.end;
  }
  return -1;
}

/// Match de token no texto sem falso positivo (`1` em `21` ou `15`).
bool textoContemTokenObra(String texto, String token) {
  final t = token.trim();
  if (t.isEmpty || texto.isEmpty) return false;

  if (t.contains('/') || t.contains('x') || t.length >= 4) {
    if (texto.contains(t)) return true;
    final tc = compactarTextoBuscaObra(t);
    final ec = compactarTextoBuscaObra(texto);
    return tc.length >= 3 && ec.contains(tc);
  }

  if (RegExp(r'^\d+$').hasMatch(t)) {
    if (t.length >= 2) {
      if (texto.contains(t)) return true;
    }
    return RegExp(r'(^|\s)' + RegExp.escape(t) + r'(\s|$|/)').hasMatch(texto);
  }

  if (RegExp(r'^[a-z]+$').hasMatch(t)) {
    // 3 letras: prefixo de palavra (tub -> tubo), sem exigir palavra inteira.
    if (t.length <= 3) {
      return RegExp(r'(^|\s)' + RegExp.escape(t)).hasMatch(texto);
    }
    if (texto.contains(t)) return true;
    return RegExp(
      r'(^|\s)' + RegExp.escape(t) + r'($|\s)',
    ).hasMatch(texto);
  }

  return texto.contains(t);
}

/// Palavras de produto (3+ letras) que devem existir no nome quando presentes na consulta.
List<String> palavrasObrigatoriasConsultaObra(List<String> tokensSignificativos) {
  return tokensSignificativos
      .where((t) => RegExp(r'^[a-z]{3,}$').hasMatch(t))
      .toList();
}

/// Limite da consulta no modo curinga [%].
const int kBuscaCuringaMaxCaracteres = 80;
const int kBuscaCuringaMaxSegmentos = 5;
const int kBuscaCuringaMinSegmento = 2;

/// Normaliza cada trecho entre `%` sem apagar o curinga
/// (o normalizador geral troca `%` por espaco).
String normalizarConsultaCuringa(
  String consultaBruta,
  String Function(String parte) normalizarParte,
) {
  final bruta = consultaBruta.trim();
  if (!bruta.contains('%')) return normalizarParte(bruta);
  return bruta
      .split('%')
      .map((p) => normalizarParte(p.trim()))
      .join('%');
}

/// Consulta com `%` entre trechos (ex.: `tub%sod%25`). So ativa se houver `%`.
bool consultaUsaModoCuringa(String consultaNormalizada) {
  if (!consultaNormalizada.contains('%')) return false;
  final semCuringa = consultaNormalizada.replaceAll('%', '').replaceAll(' ', '');
  if (semCuringa.isNotEmpty && consultaEanProvavelCompleto(semCuringa)) {
    return false;
  }
  return true;
}

/// Segmentos extraidos de uma consulta `a%b%c`.
class ConsultaCuringaParse {
  const ConsultaCuringaParse({required this.segmentos});

  final List<String> segmentos;
}

/// Divide por `%`, ignora vazios e segmentos com menos de 2 caracteres.
ConsultaCuringaParse? parseConsultaCuringa(String consultaNormalizada) {
  final bruta = consultaNormalizada.trim();
  if (bruta.isEmpty || !bruta.contains('%')) return null;
  if (bruta.length > kBuscaCuringaMaxCaracteres) return null;

  final segmentos = <String>[];
  for (final parte in bruta.split('%')) {
    final seg = parte.trim();
    if (seg.length < kBuscaCuringaMinSegmento) continue;
    segmentos.add(seg);
    if (segmentos.length > kBuscaCuringaMaxSegmentos) return null;
  }
  if (segmentos.isEmpty) return null;
  return ConsultaCuringaParse(segmentos: segmentos);
}

/// Resultado do match ordenado de segmentos curinga.
class MatchCuringaResult {
  const MatchCuringaResult({
    required this.totalSpan,
    required this.todosNoNome,
  });

  final int totalSpan;
  final bool todosNoNome;
}

/// Segmentos em ordem no [texto] (contains; digitos com limite de fronteira).
MatchCuringaResult? avaliarMatchCuringa(String texto, List<String> segmentos) {
  if (texto.isEmpty || segmentos.isEmpty) return null;
  var pos = 0;
  final indices = <int>[];
  for (final seg in segmentos) {
    final idx = indiceSegmentoCuringa(texto, seg, pos);
    if (idx < 0) return null;
    indices.add(idx);
    pos = idx + seg.length;
  }
  final inicio = indices.first;
  final fim = indices.last + segmentos.last.length;
  return MatchCuringaResult(
    totalSpan: fim - inicio,
    todosNoNome: true,
  );
}

/// Indice do segmento a partir de [inicio] (evita `20` dentro de `25`).
int indiceSegmentoCuringa(String texto, String segmento, int inicio) {
  if (inicio >= texto.length) return -1;
  final sub = texto.substring(inicio);
  if (segmento.isEmpty) return -1;

  if (RegExp(r'^\d+$').hasMatch(segmento)) {
    final re = RegExp(r'(^|\s)' + RegExp.escape(segmento) + r'(\s|$|/)');
    final m = re.firstMatch(sub);
    if (m != null) {
      return inicio + m.start + (m.group(1)?.length ?? 0);
    }
    var busca = 0;
    while (busca < sub.length) {
      final idx = sub.indexOf(segmento, busca);
      if (idx < 0) return -1;
      final abs = inicio + idx;
      if (_segmentoNumericoIsolado(texto, segmento, abs)) return abs;
      busca = idx + 1;
    }
    return -1;
  }

  final idx = sub.indexOf(segmento);
  return idx < 0 ? -1 : inicio + idx;
}

bool _segmentoNumericoIsolado(String texto, String segmento, int indice) {
  final antesOk = indice == 0 || !RegExp(r'\d').hasMatch(texto[indice - 1]);
  final depois = indice + segmento.length;
  final depoisOk =
      depois >= texto.length || !RegExp(r'\d').hasMatch(texto[depois]);
  return antesOk && depoisOk;
}

/// Texto unificado para busca curinga (nome + apelidos).
String textoBuscaCuringaProduto({
  required String nomeNormalizado,
  required List<String> apelidosNormalizados,
}) {
  if (apelidosNormalizados.isEmpty) return nomeNormalizado;
  return '$nomeNormalizado ${apelidosNormalizados.join(' ')}';
}

/// Dica curta abaixo do campo de busca (consulta PDV); null = sem helper.
String? dicaBuscaContextual(String termoBruto) {
  final termo = termoBruto.trim();
  if (termo.isEmpty) return null;
  if (termo.contains('%')) {
    return 'Trechos: use % entre partes (ex.: tub%sod%25)';
  }
  if (consultaEanProvavelCompleto(termo) || consultaPareceCodigoBarras(termo)) {
    return 'Codigo de barras — Enter confirma';
  }
  if (termo.length < 3) {
    return 'Min. 3 caracteres ou escaneie EAN';
  }
  return null;
}

/// Normaliza texto de busca (acentos, pontuacao) — espelha o motor ObjectBox.
String normalizarTextoBuscaProduto(String texto) {
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

class _ProdutoMemoriaScore {
  const _ProdutoMemoriaScore(this.produto, this.score);
  final Produto produto;
  final double score;
}

/// Busca em memoria (Terminal Leve / cache) com curingas `%` e campos basicos.
List<Produto> pesquisarProdutosEmMemoria(
  Iterable<Produto> produtos,
  String termo, {
  int offset = 0,
  int limite = 50,
  bool somenteAtivos = true,
  bool somenteInativos = false,
  bool excluirProdutosInternos = false,
}) {
  Iterable<Produto> base = produtos;
  if (excluirProdutosInternos) {
    base = base.where((p) => !produtoEhCadastroInternoSistema(p));
  }
  if (somenteInativos) {
    base = base.where((p) => !p.ativo);
  } else if (somenteAtivos) {
    base = base.where((p) => p.ativo);
  }

  final consultaBruta = termo.trim();
  if (consultaBruta.isEmpty) {
    final lista = base.toList();
    if (offset >= lista.length) return const [];
    return lista.skip(offset).take(limite).toList();
  }

  if (consultaBruta.contains('%')) {
    final consultaCuringa = normalizarConsultaCuringa(
      consultaBruta,
      normalizarTextoBuscaProduto,
    );
    if (consultaUsaModoCuringa(consultaCuringa)) {
      final curinga = parseConsultaCuringa(consultaCuringa);
      if (curinga == null) return const [];
      final scored = <_ProdutoMemoriaScore>[];
      for (final p in base) {
        final score = _scoreCuringaEmMemoria(p, curinga.segmentos);
        if (score > 0) scored.add(_ProdutoMemoriaScore(p, score));
      }
      scored.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.produto.nome.toLowerCase().compareTo(b.produto.nome.toLowerCase());
      });
      return scored.skip(offset).take(limite).map((e) => e.produto).toList();
    }
  }

  final consulta = normalizarTextoBuscaProduto(consultaBruta);
  if (consulta.isEmpty) return const [];
  final tokens = consulta
      .split(RegExp(r'\s+'))
      .where((t) => t.length >= 2)
      .toList();
  final scored = <_ProdutoMemoriaScore>[];
  for (final p in base) {
    final score = _scoreContemEmMemoria(p, consulta, tokens);
    if (score > 0) scored.add(_ProdutoMemoriaScore(p, score));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.produto.nome.toLowerCase().compareTo(b.produto.nome.toLowerCase());
  });
  return scored.skip(offset).take(limite).map((e) => e.produto).toList();
}

double _scoreCuringaEmMemoria(Produto p, List<String> segmentos) {
  final nome = normalizarTextoBuscaProduto(p.nome);
  var match = avaliarMatchCuringa(nome, segmentos);
  var todosNoNome = match != null;
  if (match == null) {
    final apelidos = parseApelidosBusca(p.apelidosBusca)
        .map(normalizarTextoBuscaProduto)
        .where((a) => a.isNotEmpty)
        .toList();
    final texto = textoBuscaCuringaProduto(
      nomeNormalizado: nome,
      apelidosNormalizados: apelidos,
    );
    match = avaliarMatchCuringa(texto, segmentos);
    if (match == null) {
      final codigo = normalizarTextoBuscaProduto(p.codigoInterno);
      final barras = normalizarTextoBuscaProduto(p.codigoBarras);
      final extra = '$codigo $barras'.trim();
      match = avaliarMatchCuringa(extra, segmentos);
      if (match == null) return 0;
      todosNoNome = false;
    } else {
      todosNoNome = false;
    }
  }

  var score = 920.0;
  score += segmentos.length * 200;
  score += (380 - match.totalSpan).clamp(0, 380);
  score += (50 - nome.length * 0.12).clamp(0, 50);
  if (todosNoNome) {
    score += 300;
  } else {
    score -= 80;
  }
  if (p.estoqueReal > 0) {
    score += p.estoqueReal > 35 ? 35 : p.estoqueReal.toDouble();
  } else {
    score -= 60;
  }
  return score;
}

double _scoreContemEmMemoria(
  Produto p,
  String consulta,
  List<String> tokens,
) {
  final nome = normalizarTextoBuscaProduto(p.nome);
  final codigo = normalizarTextoBuscaProduto(p.codigoInterno);
  final barras = normalizarTextoBuscaProduto(p.codigoBarras);
  final apelidos = normalizarTextoBuscaProduto(p.apelidosBusca);
  final impressao = normalizarTextoBuscaProduto(p.nomeImpressao);
  final blob = '$nome $impressao $codigo $barras $apelidos';

  if (codigo == consulta || barras == consulta) return 2000;
  if (codigo.startsWith(consulta) || barras.startsWith(consulta)) return 1500;
  if (nome.startsWith(consulta)) return 1200;

  if (tokens.isEmpty) {
    if (!blob.contains(consulta)) return 0;
    var score = 400.0;
    if (nome.contains(consulta)) score += 200;
    if (p.estoqueReal > 0) score += 20;
    return score;
  }

  for (final t in tokens) {
    if (!blob.contains(t)) return 0;
  }
  var score = 500.0 + tokens.length * 40;
  if (tokens.every(nome.contains)) score += 180;
  if (p.estoqueReal > 0) score += 20;
  return score;
}

/// Utilitarios compartilhados do motor de busca de produtos (PDV, cadastro, estoque).
library;

import '../model/produto.dart';

/// SKU reservado ao ERP (ex.: frete retirada futura). Nao vende no balcao.
const String kCodigoInternoFreteRetiradaFutura = '__FRETE_RET_FUTURA__';

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

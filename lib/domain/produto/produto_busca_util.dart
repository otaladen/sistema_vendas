/// Motor unico de busca de produtos: PDV, cadastro, servidor LAN e terminal leve.
///
/// [ProdutoRepository] (ObjectBox) e [ProdutoApiRepository] (terminal) montam
/// os mesmos [ProdutoBuscaDoc] e chamam [ProdutoBuscaUtil], garantindo o mesmo
/// ranking nos dois lados. O ranking usa apenas campos sincronizados do produto.
library;

import 'dart:math' as math;

import '../../data/produto_busca_sinonimos.dart';
import '../../data/produto_busca_util.dart';
import '../../model/produto.dart';
import '../pdv_busca_inteligente.dart';

enum TipoMedidaProduto { volume, massa, comprimento, area }

/// Medida/embalagem extraida do nome (ex.: `3,6L` -> volume 3600 ml).
class MedidaProduto {
  const MedidaProduto(this.tipo, this.valorBase);

  final TipoMedidaProduto tipo;

  /// ml, g, mm ou m2 conforme [tipo].
  final double valorBase;

  @override
  bool operator ==(Object other) =>
      other is MedidaProduto &&
      other.tipo == tipo &&
      other.valorBase == valorBase;

  @override
  int get hashCode => Object.hash(tipo, valorBase);

  @override
  String toString() => 'MedidaProduto($tipo, $valorBase)';
}

/// Produto pre-normalizado para busca (montado uma vez por versao do catalogo).
class ProdutoBuscaDoc {
  const ProdutoBuscaDoc({
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
    required this.medida,
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
  final MedidaProduto? medida;

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

/// Item ranqueado. Ordem: [nivel], [distanciaTypos], [posicaoTermo], medida,
/// estoque, faixa de [scoreTotal], nome. Ver [ProdutoBuscaUtil.compararResultados].
class ProdutoBuscaResultado {
  const ProdutoBuscaResultado({
    required this.doc,
    required this.nivel,
    required this.match,
    required this.bonusGiro,
    this.distanciaTypos = 0,
    this.posicaoTermo = 2,
  });

  final ProdutoBuscaDoc doc;

  /// Palavra do nome onde a 1a palavra da consulta aparece: 0 = primeira
  /// ("Tubo PVC", ou apelido), 1 = segunda ("mt Tubo ESG"), 2 = depois ou
  /// ausente ("Solda ... em Tubo").
  final int posicaoTermo;

  /// 3 = codigo/EAN/apelido exato; 2 = todos os termos no nome ou apelido;
  /// 1 = todos os termos em algum campo; 0 = parcial ou por erro de digitacao.
  final int nivel;

  /// Relevancia textual.
  final double match;

  /// Giro de venda ([Produto.vendaMediaDiaria]), limitado a [ProdutoBuscaUtil.kBonusGiroMaximo].
  final double bonusGiro;

  /// Soma das distancias de edicao usadas para aceitar termos com erro.
  final int distanciaTypos;

  Produto get produto => doc.produto;
  double get scoreTotal => match + bonusGiro;
  bool get temEstoque => doc.produto.estoqueReal > 0;
}

abstract final class ProdutoBuscaUtil {
  /// Largura da faixa de [ProdutoBuscaResultado.scoreTotal] tratada como empate.
  /// Diferencas menores (ex.: texto extra no fim do nome, giro) nao separam
  /// produtos da mesma familia; o desempate passa para medida e nome.
  static const double kFaixaScoreRanking = 300;

  static const double kBonusGiroMaximo = 120;

  static const int kLimiteResultadosPdv = 50;

  static final RegExp _reMedida = RegExp(
    r'(?<![\d.,])(\d+(?:[.,]\d+)?)\s*'
    r'(ml|litros|litro|lts|lt|l|kg|gr|g|mm|cm|m2|m²|metros|metro|mts|mt|m)'
    r'(?![a-z0-9])',
  );

  static final RegExp _reSomenteLetras4 = RegExp(r'^[a-z]{4,}$');

  static ProdutoBuscaDoc criarDoc(Produto produto) {
    final nome = normalizarTextoBuscaProduto(produto.nome);
    final descricao = normalizarTextoBuscaProduto(produto.descricao);
    final codigoInterno = normalizarTextoBuscaProduto(produto.codigoInterno);
    final codigoBarras = normalizarCodigoBarrasConsulta(produto.codigoBarras);
    final categoria = normalizarTextoBuscaProduto(produto.categoria);
    final subcategoria = normalizarTextoBuscaProduto(produto.subcategoria);
    final marca = normalizarTextoBuscaProduto(produto.marca);
    final fornecedor = normalizarTextoBuscaProduto(produto.fornecedor);
    final fabricante = normalizarTextoBuscaProduto(produto.fabricante);
    final apelidosBrutos = parseApelidosBusca(produto.apelidosBusca);
    final apelidosNormalizados = apelidosBrutos
        .map(normalizarTextoBuscaProduto)
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
    final tokensMedidas = extrairTokensMedidasDeTexto(
      [
        nome,
        descricao,
        codigoInterno,
        categoria,
        subcategoria,
        marca,
        ...apelidosNormalizados,
      ].join(' '),
    );
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
    return ProdutoBuscaDoc(
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
      medida: extrairMedidaProduto(produto.nome),
    );
  }

  static List<ProdutoBuscaDoc> criarDocs(Iterable<Produto> produtos) =>
      produtos.map(criarDoc).toList();

  /// Primeira medida do nome em unidade base (ml, g, mm, m2). Usa o nome bruto
  /// porque a normalizacao troca a virgula decimal por espaco.
  static MedidaProduto? extrairMedidaProduto(String nome) {
    final m = _reMedida.firstMatch(nome.toLowerCase());
    if (m == null) return null;
    final valor = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (valor == null) return null;
    switch (m.group(2)!) {
      case 'ml':
        return MedidaProduto(TipoMedidaProduto.volume, valor);
      case 'litros':
      case 'litro':
      case 'lts':
      case 'lt':
      case 'l':
        return MedidaProduto(TipoMedidaProduto.volume, valor * 1000);
      case 'kg':
        return MedidaProduto(TipoMedidaProduto.massa, valor * 1000);
      case 'gr':
      case 'g':
        return MedidaProduto(TipoMedidaProduto.massa, valor);
      case 'mm':
        return MedidaProduto(TipoMedidaProduto.comprimento, valor);
      case 'cm':
        return MedidaProduto(TipoMedidaProduto.comprimento, valor * 10);
      case 'm2':
      case 'm²':
        return MedidaProduto(TipoMedidaProduto.area, valor);
      default:
        return MedidaProduto(TipoMedidaProduto.comprimento, valor * 1000);
    }
  }

  static bool _incluir(
    ProdutoBuscaDoc doc, {
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

  /// Busca paginada. Termo vazio: todos os filtrados em ordem natural do nome.
  static List<Produto> pesquisar(
    Iterable<ProdutoBuscaDoc> docs,
    String termo, {
    int offset = 0,
    int limite = 50,
    bool somenteAtivos = true,
    bool somenteInativos = false,
    bool excluirProdutosInternos = false,
  }) {
    return ranquear(
      docs,
      termo,
      somenteAtivos: somenteAtivos,
      somenteInativos: somenteInativos,
      excluirProdutosInternos: excluirProdutosInternos,
    ).skip(offset).take(limite).map((r) => r.produto).toList();
  }

  /// Todos os produtos que correspondem a [termo], ja ordenados.
  static List<ProdutoBuscaResultado> ranquear(
    Iterable<ProdutoBuscaDoc> docs,
    String termo, {
    bool somenteAtivos = true,
    bool somenteInativos = false,
    bool excluirProdutosInternos = false,
  }) {
    final base = docs
        .where(
          (d) => _incluir(
            d,
            somenteAtivos: somenteAtivos,
            somenteInativos: somenteInativos,
            excluirProdutosInternos: excluirProdutosInternos,
          ),
        )
        .toList();
    final bruta = termo.trim();
    if (bruta.isEmpty) {
      base.sort(
        (a, b) => compararNomeProdutoBusca(a.produto.nome, b.produto.nome),
      );
      return base
          .map(
            (d) => ProdutoBuscaResultado(
              doc: d,
              nivel: 0,
              match: 0,
              bonusGiro: 0,
            ),
          )
          .toList();
    }

    final consultaOrdenacao = normalizarTextoBuscaProduto(bruta);
    final resultados = <ProdutoBuscaResultado>[];

    if (bruta.contains('%')) {
      final curinga = normalizarConsultaCuringa(
        bruta,
        normalizarTextoBuscaProduto,
      );
      if (consultaUsaModoCuringa(curinga)) {
        final parse = parseConsultaCuringa(curinga);
        if (parse == null) return const [];
        for (final doc in base) {
          final r = _pontuarCuringa(doc, parse.segmentos);
          if (r != null) resultados.add(r);
        }
        ordenarResultados(resultados, consultaOrdenacao);
        return resultados;
      }
    }

    if (consultaOrdenacao.trim().isEmpty) return const [];
    final consulta = _ConsultaTexto.preparar(consultaOrdenacao, base);
    for (final doc in base) {
      final r = _pontuar(doc, consulta);
      if (r != null) resultados.add(r);
    }
    ordenarResultados(resultados, consultaOrdenacao);
    return resultados;
  }

  static void ordenarResultados(
    List<ProdutoBuscaResultado> resultados,
    String consultaNormalizada,
  ) {
    final contextoCabo = ordenacaoContextualCaboAtiva(consultaNormalizada);
    resultados.sort(
      (a, b) => compararResultados(a, b, contextoCabo: contextoCabo),
    );
  }

  static int _faixa(double score) => (score / kFaixaScoreRanking).floor();

  static int compararResultados(
    ProdutoBuscaResultado a,
    ProdutoBuscaResultado b, {
    bool contextoCabo = false,
  }) {
    var c = b.nivel.compareTo(a.nivel);
    if (c != 0) return c;
    c = a.distanciaTypos.compareTo(b.distanciaTypos);
    if (c != 0) return c;
    c = a.posicaoTermo.compareTo(b.posicaoTermo);
    if (c != 0) return c;
    // Medida antes de estoque/pontuacao: 225ml, 900ml e 3,6l ficam em blocos;
    // estoque e pontuacao so ordenam dentro da mesma embalagem.
    c = compararGrupoMedida(a.doc, b.doc, contextoCabo: contextoCabo);
    if (c != 0) return c;
    if (a.temEstoque != b.temEstoque) return a.temEstoque ? -1 : 1;
    c = _faixa(b.scoreTotal).compareTo(_faixa(a.scoreTotal));
    if (c != 0) return c;
    return compararDesempate(a.doc, b.doc);
  }

  /// Cabos (bitola eletrica, generico, especial) e depois medida/embalagem.
  static int compararGrupoMedida(
    ProdutoBuscaDoc a,
    ProdutoBuscaDoc b, {
    bool contextoCabo = false,
  }) {
    if (contextoCabo) {
      final c = grupoOrdenacaoCaboProduto(a.produto.nome)
          .compareTo(grupoOrdenacaoCaboProduto(b.produto.nome));
      if (c != 0) return c;
    }
    return compararMedidas(a.medida, b.medida);
  }

  /// Mesma relevancia, medida, estoque e faixa: nome e marca.
  static int compararDesempate(ProdutoBuscaDoc a, ProdutoBuscaDoc b) {
    var c = compararNomeProdutoBusca(a.produto.nome, b.produto.nome);
    if (c != 0) return c;
    c = a.marcaNormalizada.compareTo(b.marcaNormalizada);
    if (c != 0) return c;
    return a.produto.id.compareTo(b.produto.id);
  }

  /// Com medida antes de sem medida; por tipo; valor crescente.
  static int compararMedidas(MedidaProduto? a, MedidaProduto? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.tipo.index.compareTo(b.tipo.index);
    if (c != 0) return c;
    return a.valorBase.compareTo(b.valorBase);
  }

  static double bonusGiro(Produto produto) {
    final v = produto.vendaMediaDiaria;
    if (v <= 0 || !v.isFinite) return 0;
    return math.min(kBonusGiroMaximo, math.log(1 + v * 30) * 25);
  }

  /// EAN exato (campo principal ou alternativo em apelidos).
  static Produto? buscarPorCodigoBarras(
    Iterable<ProdutoBuscaDoc> docs,
    String termo, {
    bool somenteAtivos = true,
  }) {
    if (!consultaPareceCodigoBarras(termo)) return null;
    final dig = normalizarCodigoBarrasConsulta(termo);
    if (dig.isEmpty) return null;
    for (final doc in docs) {
      if (!doc.correspondeCodigoBarras(dig)) continue;
      if (somenteAtivos && !doc.produto.ativo) continue;
      return doc.produto;
    }
    return null;
  }

  static Produto? buscarPorCodigoInternoExato(
    Iterable<ProdutoBuscaDoc> docs,
    String termo, {
    bool somenteAtivos = true,
  }) {
    final norm = normalizarTextoBuscaProduto(termo.trim());
    if (norm.isEmpty) return null;
    for (final doc in docs) {
      if (!_incluir(
        doc,
        somenteAtivos: somenteAtivos,
        somenteInativos: false,
        excluirProdutosInternos: true,
      )) {
        continue;
      }
      if (doc.correspondeCodigoInterno(norm)) return doc.produto;
    }
    return null;
  }

  /// PDV: EAN -> SKU exato -> ranking. Seleciona sozinho so com 1 correspondencia.
  static PdvPesquisaResolvida resolverPesquisaPdv(
    Iterable<ProdutoBuscaDoc> docs,
    String termo, {
    bool somenteAtivos = true,
    Produto? Function(String termo)? resolverCodigoBarras,
  }) {
    final consulta = termo.trim();
    if (consulta.isEmpty) return PdvPesquisaResolvida.vazia;

    final barras = resolverCodigoBarras != null
        ? resolverCodigoBarras(consulta)
        : buscarPorCodigoBarras(docs, consulta, somenteAtivos: somenteAtivos);
    if (barras != null) {
      return PdvPesquisaResolvida(
        produtos: [barras],
        totalCorrespondencias: 1,
        produtoAuto: barras,
        motivoAuto: PdvBuscaAutoMotivo.codigoBarras,
      );
    }

    final sku = buscarPorCodigoInternoExato(
      docs,
      consulta,
      somenteAtivos: somenteAtivos,
    );
    if (sku != null) {
      return PdvPesquisaResolvida(
        produtos: [sku],
        totalCorrespondencias: 1,
        produtoAuto: sku,
        motivoAuto: PdvBuscaAutoMotivo.codigoInterno,
      );
    }

    final ranking = ranquear(
      docs,
      consulta,
      somenteAtivos: somenteAtivos,
      excluirProdutosInternos: true,
    );
    if (ranking.length == 1) {
      return PdvPesquisaResolvida(
        produtos: [ranking.first.produto],
        totalCorrespondencias: 1,
        produtoAuto: ranking.first.produto,
        motivoAuto: PdvBuscaAutoMotivo.unicoResultado,
      );
    }
    return PdvPesquisaResolvida(
      produtos: ranking
          .take(kLimiteResultadosPdv)
          .map((r) => r.produto)
          .toList(),
      totalCorrespondencias: ranking.length,
    );
  }

  static ProdutoBuscaResultado? _pontuarCuringa(
    ProdutoBuscaDoc doc,
    List<String> segmentos,
  ) {
    final nome = doc.nomeNormalizado;
    var match = avaliarMatchCuringa(nome, segmentos);
    final todosNoNome = match != null;
    if (match == null) {
      match = avaliarMatchCuringa(
        textoBuscaCuringaProduto(
          nomeNormalizado: nome,
          apelidosNormalizados: doc.apelidosNormalizados,
        ),
        segmentos,
      );
      match ??= avaliarMatchCuringa(
        '${doc.codigoInternoNormalizado} ${doc.codigoBarrasNormalizado}'.trim(),
        segmentos,
      );
      if (match == null) return null;
    }

    var score = 920.0;
    score += segmentos.length * 200;
    score += math.max(0, 380 - match.totalSpan);
    score += todosNoNome ? 300 : -80;
    return ProdutoBuscaResultado(
      doc: doc,
      nivel: todosNoNome ? 2 : 1,
      match: score,
      bonusGiro: bonusGiro(doc.produto),
      posicaoTermo: _posicaoTermo(doc, segmentos.first),
    );
  }

  static int _posicaoTermo(ProdutoBuscaDoc doc, String termo) {
    if (termo.isEmpty) return 2;
    if (doc.apelidosNormalizados.any((a) => a.startsWith(termo))) return 0;
    final palavras = doc.nomeNormalizado.split(RegExp(r'[\s/]+'));
    for (var i = 0; i < palavras.length && i < 2; i++) {
      if (palavras[i].startsWith(termo)) return i;
    }
    return 2;
  }

  /// Nome, apelidos, marca/fabricante, categoria e descricao.
  static bool _tokenEmCamposTexto(ProdutoBuscaDoc doc, String token) {
    if (textoContemTokenObra(doc.nomeNormalizado, token)) return true;
    if (_tokenEmApelidos(doc, token)) return true;
    return textoContemTokenObra(doc.marcaNormalizada, token) ||
        textoContemTokenObra(doc.fabricanteNormalizado, token) ||
        textoContemTokenObra(doc.categoriaNormalizada, token) ||
        textoContemTokenObra(doc.subcategoriaNormalizada, token) ||
        textoContemTokenObra(doc.descricaoNormalizada, token);
  }

  static bool _tokenEmApelidos(ProdutoBuscaDoc doc, String token) {
    for (final a in doc.apelidosNormalizados) {
      if (textoContemTokenObra(a, token)) return true;
    }
    return false;
  }

  static bool _tokenEmCodigos(ProdutoBuscaDoc doc, String token) {
    final codigo = doc.codigoInternoNormalizado;
    if (codigo.isNotEmpty) {
      if (skuBuscaCorrespondeExato(token, codigo)) return true;
      if (skuBuscaPontuacaoParcial(token, codigo) != null) return true;
      if (token.length >= 3 && codigo.contains(token)) return true;
    }
    final dig = somenteDigitosBusca(token);
    if (dig.isNotEmpty && dig.length == token.length) {
      if (doc.correspondeCodigoBarras(dig)) return true;
      if (dig.length >= 6 && doc.codigoBarrasNormalizado.endsWith(dig)) {
        return true;
      }
    }
    return false;
  }

  static bool _tokenDireto(ProdutoBuscaDoc doc, String token) =>
      _tokenEmCamposTexto(doc, token) ||
      _tokenEmCodigos(doc, token) ||
      textoContemTokenObra(doc.fornecedorNormalizado, token);

  static ProdutoBuscaResultado? _pontuar(
    ProdutoBuscaDoc doc,
    _ConsultaTexto q,
  ) {
    final nome = doc.nomeNormalizado;
    final nomeCompacto = doc.nomeCompacto;
    final descricao = doc.descricaoNormalizada;
    final consultaNormalizada = q.consultaNormalizada;

    var distanciaTypos = 0;
    for (final palavra in q.palavrasObrigatorias) {
      if (_tokenEmCamposTexto(doc, palavra)) continue;
      final d = q.distanciaTypo(doc, palavra);
      if (d == null) return null;
      distanciaTypos += d;
    }

    final codigoInterno = doc.codigoInternoNormalizado;
    final codigoBarras = doc.codigoBarrasNormalizado;
    final consultaDigitos = q.consultaDigitos;
    final camposSecundarios = [
      doc.categoriaNormalizada,
      doc.subcategoriaNormalizada,
      doc.marcaNormalizada,
      doc.fornecedorNormalizado,
      doc.fabricanteNormalizado,
      descricao,
    ];

    double score = 0;
    var codigoExato = false;

    if (consultaDigitos.isNotEmpty && doc.correspondeCodigoBarras(consultaDigitos)) {
      score += 1500;
      if (q.consultaSoDigitos) codigoExato = true;
    } else if (consultaDigitos.length >= 6 &&
        codigoBarras.isNotEmpty &&
        codigoBarras.endsWith(consultaDigitos)) {
      score += 900;
    }
    if (codigoInterno.isNotEmpty &&
        (consultaNormalizada == codigoInterno ||
            skuBuscaCorrespondeExato(consultaNormalizada, codigoInterno))) {
      score += 1000;
      codigoExato = true;
    } else {
      final skuParcial =
          skuBuscaPontuacaoParcial(consultaNormalizada, codigoInterno);
      if (skuParcial != null) score += skuParcial;
    }
    for (final apelido in doc.apelidosNormalizados) {
      if (apelido == consultaNormalizada) {
        score += 980;
        codigoExato = true;
      } else if (apelido.contains(consultaNormalizada) &&
          consultaNormalizada.length >= 3) {
        score += 520;
      }
    }
    if (q.consultaCompacta.length >= 5 &&
        nomeCompacto.contains(q.consultaCompacta)) {
      score += 1400;
    }
    for (final frase in q.frases) {
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
    if (nome.startsWith(consultaNormalizada)) score += 700;
    if (nome.contains(consultaNormalizada)) score += 450;
    if (consultaNormalizada.length >= 3 &&
        descricao.contains(consultaNormalizada)) {
      score += 280;
    }
    if (doc.categoriaNormalizada.contains(consultaNormalizada) ||
        doc.marcaNormalizada.contains(consultaNormalizada) ||
        doc.fabricanteNormalizado.contains(consultaNormalizada)) {
      score += 200;
    }

    final tokens = q.tokensSignificativos;
    var tokensNoNomeOuApelido = 0;
    var tokensDiretos = 0;
    var tokensSigMatch = 0;
    for (final token in tokens) {
      if (token.isEmpty) continue;
      final noNome = textoContemTokenObra(nome, token);
      final noApelido = !noNome && _tokenEmApelidos(doc, token);
      if (noNome || noApelido) {
        tokensNoNomeOuApelido++;
        tokensDiretos++;
      } else if (_tokenDireto(doc, token)) {
        tokensDiretos++;
      }
      final noDescricao = textoContemTokenObra(descricao, token);
      if (noNome || noDescricao) {
        tokensSigMatch++;
        if (noNome) {
          score += token.contains('/') || token.contains('x') ? 240 : 180;
        } else {
          score += 70;
        }
      } else if (noApelido) {
        score += 160;
      }
    }

    if (tokens.length >= 2) {
      if (tokensNoNomeOuApelido == tokens.length) {
        score += 520;
      } else {
        score -= 120.0 * (tokens.length - tokensNoNomeOuApelido);
      }
      if (sequenciaTokensNoTexto(nome, tokens)) score += 380;
    }

    var tokensExpMatch = 0;
    for (final token in q.tokensExpandidos) {
      if (token.isEmpty) continue;
      var tokenMatched = true;
      final tokenDigitos = somenteDigitosBusca(token);
      if (tokenDigitos.isNotEmpty && doc.correspondeCodigoBarras(tokenDigitos)) {
        score += 380;
      } else if (codigoInterno == token ||
          skuBuscaCorrespondeExato(token, codigoInterno)) {
        score += 320;
      } else if (doc.apelidosNormalizados.any(
        (a) => a == token || (a.contains(token) && token.length >= 3),
      )) {
        score += 260;
      } else if (textoContemTokenObra(nome, token)) {
        score += token.length >= 4 || token.contains('/') ? 150 : 60;
      } else if (camposSecundarios.any((c) => textoContemTokenObra(c, token))) {
        score += 50;
      } else {
        final d = q.distanciaTypo(doc, token);
        if (d != null) {
          score += 60.0 - 20 * d;
        } else {
          tokenMatched = false;
        }
      }
      if (tokenMatched) tokensExpMatch++;
    }

    if (tokens.isEmpty) {
      if (score <= 0) return null;
    } else if (tokensSigMatch == tokens.length) {
      score += 120;
    } else if (tokensExpMatch == 0 && tokensDiretos == 0 && !codigoExato) {
      return null;
    }

    final int nivel;
    if (codigoExato) {
      nivel = 3;
    } else if (tokens.isNotEmpty && tokensNoNomeOuApelido == tokens.length) {
      nivel = 2;
    } else if (tokens.isNotEmpty && tokensDiretos == tokens.length) {
      nivel = 1;
    } else {
      nivel = 0;
    }

    return ProdutoBuscaResultado(
      doc: doc,
      nivel: nivel,
      match: score,
      bonusGiro: bonusGiro(doc.produto),
      distanciaTypos: distanciaTypos,
      posicaoTermo: _posicaoTermo(doc, q.primeiraPalavra),
    );
  }
}

/// Consulta pre-processada + decisao de quais termos aceitam erro de digitacao.
class _ConsultaTexto {
  _ConsultaTexto._({
    required this.consultaNormalizada,
    required this.consultaCompacta,
    required this.consultaDigitos,
    required this.consultaSoDigitos,
    required this.frases,
    required this.tokensSignificativos,
    required this.tokensExpandidos,
    required this.palavrasObrigatorias,
    required this.tokensComTypo,
  });

  final String consultaNormalizada;
  final String consultaCompacta;

  String get primeiraPalavra =>
      consultaNormalizada.trim().split(RegExp(r'\s+')).first;
  final String consultaDigitos;
  final bool consultaSoDigitos;
  final List<String> frases;
  final List<String> tokensSignificativos;
  final List<String> tokensExpandidos;
  final List<String> palavrasObrigatorias;

  /// Termos sem nenhuma ocorrencia direta no catalogo filtrado. So eles usam
  /// distancia de edicao: se "cabo" existe, "cano" nao entra como erro de "cabo".
  final Set<String> tokensComTypo;

  final Map<String, Map<String, int>> _memoDistancia = {};

  static _ConsultaTexto preparar(
    String consultaNormalizada,
    List<ProdutoBuscaDoc> base,
  ) {
    final parse = tokenizarConsultaObra(consultaNormalizada);
    final significativos = parse.tokensSignificativos;
    final expandidos = {
      ...significativos,
      ...expandirTokensBuscaComSinonimos(significativos),
      ...expandirTokensMedidasObra(significativos),
    }.toList();

    final candidatosTypo = significativos
        .where(ProdutoBuscaUtil._reSomenteLetras4.hasMatch)
        .toSet();
    final comTypo = <String>{};
    for (final token in candidatosTypo) {
      var ocorre = false;
      for (final doc in base) {
        if (ProdutoBuscaUtil._tokenDireto(doc, token)) {
          ocorre = true;
          break;
        }
      }
      if (!ocorre) comTypo.add(token);
    }

    return _ConsultaTexto._(
      consultaNormalizada: consultaNormalizada,
      consultaCompacta: parse.consultaCompacta,
      consultaDigitos: somenteDigitosBusca(consultaNormalizada),
      consultaSoDigitos: textoSomenteDigitosBusca(consultaNormalizada),
      frases: parse.frases,
      tokensSignificativos: significativos,
      tokensExpandidos: expandidos,
      palavrasObrigatorias: palavrasObrigatoriasConsultaObra(significativos),
      tokensComTypo: comTypo,
    );
  }

  /// Menor distancia do [token] a uma palavra do produto, se dentro do limite.
  int? distanciaTypo(ProdutoBuscaDoc doc, String token) {
    if (!tokensComTypo.contains(token)) return null;
    final limite = _limiteDistancia(token);
    final memo = _memoDistancia.putIfAbsent(token, () => {});
    var melhor = limite + 1;
    for (final palavra in doc.palavrasBusca) {
      if ((palavra.length - token.length).abs() > limite) continue;
      final d = memo.putIfAbsent(palavra, () => _levenshtein(token, palavra));
      if (d < melhor) {
        melhor = d;
        if (melhor == 0) break;
      }
    }
    return melhor <= limite ? melhor : null;
  }

  static int _limiteDistancia(String token) {
    if (token.length <= 4) return 1;
    if (token.length <= 8) return 2;
    return 3;
  }

  static int _levenshtein(String a, String b) {
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
}

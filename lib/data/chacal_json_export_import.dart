import 'dart:convert';
import 'dart:io';

import '../domain/importacao/produto_importacao_linha.dart';
import '../domain/importacao/produto_importacao_util.dart';
import 'produto_busca_util.dart';

/// Le produtos de exportacao JSON do Chacal (ex.: PRODUTOS.txt).
class ChacalJsonExportImport {
  ChacalJsonExportImport._();

  static ({List<ProdutoImportacaoLinha> linhas, int pulados}) lerArquivo({
    required String caminhoArquivo,
    bool incluirInativos = false,
  }) {
    var texto = File(caminhoArquivo).readAsStringSync(encoding: utf8);
    if (texto.isNotEmpty && texto.codeUnitAt(0) == 0xFEFF) {
      texto = texto.substring(1);
    }
    final trimmed = texto.trimLeft();
    if (!trimmed.startsWith('{')) {
      throw Exception(
        'Arquivo nao parece exportacao JSON do Chacal (esperado objeto com "produto").',
      );
    }

    final decoded = jsonDecode(texto);
    if (decoded is! Map) {
      throw Exception('JSON Chacal invalido: raiz deve ser um objeto.');
    }
    final root = Map<String, dynamic>.from(decoded);

    final produtosRaw = root['produto'];
    if (produtosRaw is! List || produtosRaw.isEmpty) {
      throw Exception(
        'Arquivo sem lista "produto". Confira se e o PRODUTOS.txt exportado no Chacal.',
      );
    }

    final marca = _mapLookup(root['produto_marca'], 'ID_PRODUTO_MARCA', 'NOME');
    final familia =
        _mapLookup(root['produto_familia'], 'ID_PRODUTO_FAMILIA', 'NOME');
    final grupo = _mapLookup(root['produto_grupo'], 'ID_PRODUTO_GRUPO', 'NOME');
    final subgrupo =
        _mapLookup(root['produto_sub_grupo'], 'ID_PRODUTO_SUB_GRUPO', 'NOME');
    final unidade =
        _mapLookup(root['produto_unidade'], 'ID_PRODUTO_UNIDADE', 'SIGLA');

    // Export JSON do Chacal nao traz saldo de estoque.
    final estoquePorProduto = <int, double>{};
    final estoqueRaw = root['produto_estoque'];
    if (estoqueRaw is List) {
      for (final item in estoqueRaw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final pid = _asInt(m['ID_PRODUTO']);
        if (pid == null) continue;
        estoquePorProduto[pid] =
            (estoquePorProduto[pid] ?? 0) + _asDouble(m['SALDO']);
      }
    }
    final temEstoqueNoArquivo = estoquePorProduto.isNotEmpty;

    final linhas = <ProdutoImportacaoLinha>[];
    var pulados = 0;

    for (final item in produtosRaw) {
      if (item is! Map) {
        pulados++;
        continue;
      }
      final row = Map<String, dynamic>.from(item);
      final inativo = _txt(row['INATIVO']);
      if (!incluirInativos &&
          !ProdutoImportacaoUtil.ativoDeFlagLegado(inativo)) {
        pulados++;
        continue;
      }

      var codigoBruto = ProdutoImportacaoUtil.codigoInternoChacal(
        codigoInternoBruto: _txt(row['CODIGO_INTERNO']),
        gtin: _txt(row['GTIN']),
      );
      final nome = _txt(row['NOME']);
      final gtin = _txt(row['GTIN']);
      if (nome.isEmpty) {
        pulados++;
        continue;
      }
      if (codigoBruto.isEmpty && gtin.isEmpty && _txt(row['ID_PRODUTO']).isEmpty) {
        pulados++;
        continue;
      }

      final codigo = codigoBruto.isEmpty
          ? ''
          : normalizarCodigoInternoPersistido(codigoBruto);
      if (codigoBruto.isNotEmpty && codigo.isEmpty) {
        pulados++;
        continue;
      }

      final nomePdv = _txt(row['NOME_PDV']);
      final preco1 = _asDouble(row['PRECO1']);
      final preco2 = _asDouble(row['PRECO2']);
      final preco3 = _asDouble(row['PRECO3']);

      var precocusto = _asDouble(row['VALOR_COMPRA']);
      if (precocusto <= 0) {
        precocusto = _asDouble(row['VALOR_COMPRA_LIQUIDO']);
      }

      var und = _lookup(unidade, row['ID_PRODUTO_UNIDADE']);
      if (und.isEmpty) und = _txt(row['SIGLA']);
      if (und.isEmpty) und = _txt(row['UNIDADE_COMPRA']);
      if (und.isEmpty) und = 'UN';

      final pid = _asInt(row['ID_PRODUTO']);
      final est = pid == null ? 0.0 : (estoquePorProduto[pid] ?? 0.0);
      final estInt = est.round();
      final estMin = _asDouble(row['ESTOQUE_MINIMO']).round();

      linhas.add(
        ProdutoImportacaoLinha(
          codigoInterno: codigo,
          nome: nome,
          descricao: nomePdv.isNotEmpty && nomePdv != nome ? nomePdv : '',
          preco1: preco1,
          preco2: preco2,
          preco3: preco3,
          precoCusto: precocusto,
          custoMedio: _asDouble(row['CUSTO_MEDIO_LIQUIDO']),
          estoque: estInt < 0 ? 0 : estInt,
          quantidadeMinima: estMin < 0 ? 0 : estMin,
          unidade: und,
          marca: _lookup(marca, row['ID_PRODUTO_MARCA']),
          codigoBarras: ProdutoImportacaoUtil.normalizarCodigoBarras(
            gtin: gtin,
          ),
          ncm: ProdutoImportacaoUtil.normalizarNcm(_txt(row['NCM'])),
          familia: _lookup(familia, row['ID_PRODUTO_FAMILIA']),
          grupo: _lookup(grupo, row['ID_PRODUTO_GRUPO']),
          subgrupo: _lookup(subgrupo, row['ID_PRODUTO_SUB_GRUPO']),
          ativo: ProdutoImportacaoUtil.ativoDeFlagLegado(inativo),
          subcategoriaFallback: 'Importacao Chacal',
          manterEstoqueAoAtualizar: !temEstoqueNoArquivo,
        ),
      );
    }

    return (linhas: linhas, pulados: pulados);
  }

  /// Detecta export JSON Chacal por conteudo (ex.: PRODUTOS.txt).
  static bool pareceArquivoJsonChacal(String caminho) {
    final lower = caminho.toLowerCase();
    if (lower.endsWith('.json')) return true;
    if (!lower.endsWith('.txt')) return false;
    try {
      final raf = File(caminho).openSync(mode: FileMode.read);
      try {
        final buf = raf.readSync(256);
        final head = utf8.decode(buf, allowMalformed: true).trimLeft();
        return head.startsWith('{') &&
            (head.contains('"produto"') || head.contains('produto_'));
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  static Map<int, String> _mapLookup(
    Object? raw,
    String idCol,
    String nameCol,
  ) {
    if (raw is! List) return {};
    final out = <int, String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = _asInt(m[idCol]);
      if (id == null) continue;
      final nome = _txt(m[nameCol]);
      if (nome.isEmpty) continue;
      out[id] = nome;
    }
    return out;
  }

  static String _lookup(Map<int, String> map, Object? idRaw) {
    final id = _asInt(idRaw);
    if (id == null) return '';
    return map[id] ?? '';
  }

  static String _txt(Object? v) => v?.toString().trim() ?? '';

  static double _asDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return ProdutoImportacaoUtil.parseMonetario(v.toString());
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt;
    return double.tryParse(s.replaceAll(',', '.'))?.round();
  }
}

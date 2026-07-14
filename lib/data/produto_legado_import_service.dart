import '../domain/importacao/produto_importacao_linha.dart';
import '../domain/importacao/produto_importacao_util.dart';
import '../model/produto.dart';
import 'produto_busca_util.dart';
import 'produto_repository.dart';

class ProdutoLegadoImportResumo {
  const ProdutoLegadoImportResumo({
    required this.inseridos,
    required this.atualizados,
    required this.ignorados,
    required this.erros,
  });

  final int inseridos;
  final int atualizados;
  final int ignorados;
  final List<String> erros;

  int get totalProcessados => inseridos + atualizados;
}

/// Grava linhas de importacao legada (Chacal, CSV enriquecido) no repositorio.
class ProdutoLegadoImportService {
  ProdutoLegadoImportService._();

  static ProdutoLegadoImportResumo importar({
    required ProdutoRepository produtoRepository,
    required List<ProdutoImportacaoLinha> linhas,
    required bool atualizarExistentes,
    void Function(int atual, int total)? onProgresso,
  }) {
    var inseridos = 0;
    var atualizados = 0;
    var ignorados = 0;
    final erros = <String>[];

    final skusOcupados = <String>{
      for (final p in produtoRepository.listarTodos())
        if (normalizarCodigoInternoPersistido(p.codigoInterno).isNotEmpty)
          normalizarCodigoInternoPersistido(p.codigoInterno),
    };

    for (var i = 0; i < linhas.length; i++) {
      onProgresso?.call(i + 1, linhas.length);
      final linha = linhas[i];
      if (linha.nome.trim().isEmpty) {
        ignorados++;
        continue;
      }

      final barras = ProdutoImportacaoUtil.normalizarCodigoBarras(
        gtin: linha.codigoBarras,
        codigoBarras: linha.codigoBarras,
      );
      var codigo = normalizarCodigoInternoPersistido(linha.codigoInterno);
      if (skuPareceCodigoBarrasGtin(codigo)) codigo = '';

      final existente = _resolverExistente(
        produtoRepository: produtoRepository,
        codigo: codigo,
        barras: barras,
      );
      if (existente != null && !atualizarExistentes) {
        ignorados++;
        continue;
      }

      final skuFinal = _resolverSkuFinal(
        existente: existente,
        codigoInformado: codigo,
        skusOcupados: skusOcupados,
      );

      final produto = linha
          .copyComCodigoInterno(skuFinal)
          .paraProduto(existente: existente);
      try {
        final idSalvo = produtoRepository.salvar(
          produto,
          motivoAjusteEstoque: 'Importacao cadastro legado',
        );
        skusOcupados.add(skuFinal);
        if (linha.custoMedio <= 0) {
          produtoRepository.sincronizarCustoMedioInteligenteParaProduto(
            idSalvo,
          );
        }
        if (existente != null) {
          atualizados++;
        } else {
          inseridos++;
        }
      } on ProdutoSkuDuplicadoException catch (e) {
        erros.add('Codigo $skuFinal: $e');
      }
    }

    return ProdutoLegadoImportResumo(
      inseridos: inseridos,
      atualizados: atualizados,
      ignorados: ignorados,
      erros: erros,
    );
  }

  /// Importacao otimizada: mapa por SKU/barras, lote sem notify e yield na UI.
  static Future<ProdutoLegadoImportResumo> importarAsync({
    required ProdutoRepository produtoRepository,
    required List<ProdutoImportacaoLinha> linhas,
    required bool atualizarExistentes,
    void Function(int atual, int total)? onProgresso,
  }) async {
    return produtoRepository.executarImportacaoEmLote(() async {
      var inseridos = 0;
      var atualizados = 0;
      var ignorados = 0;
      final erros = <String>[];

      final porCodigo = <String, int>{};
      final porBarras = <String, int>{};
      final skusOcupados = <String>{};

      for (final p in produtoRepository.listarTodos()) {
        final c = normalizarCodigoInternoPersistido(p.codigoInterno);
        if (c.isNotEmpty) {
          porCodigo[c] = p.id;
          skusOcupados.add(c);
        }
        final b = ProdutoImportacaoUtil.normalizarCodigoBarras(
          codigoBarras: p.codigoBarras,
        );
        if (b.isNotEmpty) porBarras[b] = p.id;
      }

      final total = linhas.length;
      for (var i = 0; i < total; i++) {
        if (i == 0 || (i + 1) % 15 == 0 || i + 1 == total) {
          onProgresso?.call(i + 1, total);
          await Future<void>.delayed(Duration.zero);
        }

        final linha = linhas[i];
        if (linha.nome.trim().isEmpty) {
          ignorados++;
          continue;
        }

        final barras = ProdutoImportacaoUtil.normalizarCodigoBarras(
          gtin: linha.codigoBarras,
          codigoBarras: linha.codigoBarras,
        );
        var codigo = normalizarCodigoInternoPersistido(linha.codigoInterno);
        if (skuPareceCodigoBarrasGtin(codigo)) codigo = '';

        int? idExistente;
        if (codigo.isNotEmpty) idExistente = porCodigo[codigo];
        if (idExistente == null && barras.isNotEmpty) {
          idExistente = porBarras[barras];
        }
        // Importacao antiga usou GTIN como SKU.
        if (idExistente == null && barras.isNotEmpty) {
          idExistente = porCodigo[barras];
        }

        if (idExistente != null && !atualizarExistentes) {
          ignorados++;
          continue;
        }

        final existente = idExistente == null
            ? null
            : produtoRepository.obterPorId(idExistente);

        final skuFinal = _resolverSkuFinal(
          existente: existente,
          codigoInformado: codigo,
          skusOcupados: skusOcupados,
        );

        final produto = linha
            .copyComCodigoInterno(skuFinal)
            .paraProduto(existente: existente);

        try {
          final idSalvo = produtoRepository.salvar(
            produto,
            motivoAjusteEstoque: 'Importacao cadastro legado',
          );
          skusOcupados.add(skuFinal);
          porCodigo[skuFinal] = idSalvo;
          if (barras.isNotEmpty) porBarras[barras] = idSalvo;
          // Libera SKU antigo estilo barras, se houve renumeracao.
          if (existente != null) {
            final antigo = normalizarCodigoInternoPersistido(
              existente.codigoInterno,
            );
            if (antigo.isNotEmpty &&
                antigo != skuFinal &&
                skuPareceCodigoBarrasGtin(antigo)) {
              porCodigo.remove(antigo);
              skusOcupados.remove(antigo);
            }
          }
          if (existente != null) {
            atualizados++;
          } else {
            inseridos++;
          }
        } on ProdutoSkuDuplicadoException catch (e) {
          erros.add('Codigo $skuFinal: $e');
        } catch (e) {
          erros.add('Codigo $skuFinal: $e');
        }
      }

      onProgresso?.call(total, total);
      return ProdutoLegadoImportResumo(
        inseridos: inseridos,
        atualizados: atualizados,
        ignorados: ignorados,
        erros: erros,
      );
    });
  }

  /// Troca SKUs estilo codigo de barras (8+ digitos) por 1, 2, 3...
  static Future<int> renumerarSkusBarrasParaSequenciais({
    required ProdutoRepository produtoRepository,
    void Function(int atual, int total)? onProgresso,
  }) async {
    return produtoRepository.executarImportacaoEmLote(() async {
      final todos = produtoRepository
          .listarTodos()
          .where((p) => !produtoEhCadastroInternoSistema(p))
          .toList();

      final ocupadosCurtos = <int>{};
      final aRenumerar = <Produto>[];
      for (final p in todos) {
        if (skuPareceCodigoBarrasGtin(p.codigoInterno)) {
          aRenumerar.add(p);
          continue;
        }
        if (skuEhNumericoSequencialCurto(p.codigoInterno)) {
          final n = skuComoInteiroSequencial(p.codigoInterno);
          if (n != null) ocupadosCurtos.add(n);
        }
      }

      aRenumerar.sort((a, b) => a.id.compareTo(b.id));
      final total = aRenumerar.length;
      var next = 1;
      var feitos = 0;

      for (final p in aRenumerar) {
        while (ocupadosCurtos.contains(next)) {
          next++;
        }
        final sku = '$next';
        // Se o codigo de barras estiver vazio, preserva o GTIN que estava no SKU.
        final antigoDigitos = somenteDigitosBusca(p.codigoInterno);
        if (p.codigoBarras.trim().isEmpty && antigoDigitos.length >= 8) {
          p.codigoBarras = antigoDigitos;
        }
        p.codigoInterno = sku;
        produtoRepository.salvar(
          p,
          motivoAjusteEstoque: 'Renumeracao SKU sequencial',
        );
        ocupadosCurtos.add(next);
        next++;
        feitos++;
        if (feitos == 1 || feitos % 20 == 0 || feitos == total) {
          onProgresso?.call(feitos, total);
          await Future<void>.delayed(Duration.zero);
        }
      }
      return feitos;
    });
  }

  static Produto? _resolverExistente({
    required ProdutoRepository produtoRepository,
    required String codigo,
    required String barras,
  }) {
    if (codigo.isNotEmpty) {
      final porSku = produtoRepository.obterPorCodigoInterno(codigo);
      if (porSku != null) return porSku;
    }
    if (barras.isNotEmpty) {
      final porBarrasAntigas = produtoRepository.obterPorCodigoInterno(barras);
      if (porBarrasAntigas != null) return porBarrasAntigas;
    }
    return null;
  }

  static String _resolverSkuFinal({
    required Produto? existente,
    required String codigoInformado,
    required Set<String> skusOcupados,
  }) {
    if (existente != null &&
        skuEhNumericoSequencialCurto(existente.codigoInterno)) {
      return normalizarCodigoInternoPersistido(existente.codigoInterno);
    }
    if (codigoInformado.isNotEmpty &&
        !skuPareceCodigoBarrasGtin(codigoInformado)) {
      return codigoInformado;
    }
    var sku = proximoSkuNumericoSequencial(skusOcupados);
    while (skusOcupados.contains(sku)) {
      final n = int.tryParse(sku) ?? 0;
      sku = '${n + 1}';
    }
    return sku;
  }
}

extension on ProdutoImportacaoLinha {
  ProdutoImportacaoLinha copyComCodigoInterno(String codigo) {
    return ProdutoImportacaoLinha(
      codigoInterno: codigo,
      nome: nome,
      descricao: descricao,
      preco1: preco1,
      preco2: preco2,
      preco3: preco3,
      precoCusto: precoCusto,
      custoMedio: custoMedio,
      estoque: estoque,
      quantidadeMinima: quantidadeMinima,
      unidade: unidade,
      marca: marca,
      fabricante: fabricante,
      codigoBarras: codigoBarras,
      ncm: ncm,
      familia: familia,
      grupo: grupo,
      subgrupo: subgrupo,
      ativo: ativo,
      subcategoriaFallback: subcategoriaFallback,
      manterEstoqueAoAtualizar: manterEstoqueAoAtualizar,
    );
  }
}

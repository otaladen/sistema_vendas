import '../../domain/produto_embalagem.dart';
import '../../model/produto.dart';
import 'categoria_importacao_mapper.dart';
import 'produto_importacao_util.dart';

/// Linha normalizada pronta para gravar no cadastro.
class ProdutoImportacaoLinha {
  const ProdutoImportacaoLinha({
    required this.codigoInterno,
    required this.nome,
    this.descricao = '',
    this.preco1 = 0,
    this.preco2 = 0,
    this.preco3 = 0,
    this.precoCusto = 0,
    this.custoMedio = 0,
    this.estoque = 0,
    this.quantidadeMinima = 0,
    this.unidade = 'UN',
    this.marca = '',
    this.fabricante = '',
    this.codigoBarras = '',
    this.ncm = '',
    this.familia = '',
    this.grupo = '',
    this.subgrupo = '',
    this.ativo = true,
    this.subcategoriaFallback = 'Importacao legado',
    this.manterEstoqueAoAtualizar = false,
  });

  final String codigoInterno;
  final String nome;
  final String descricao;
  final double preco1;
  final double preco2;
  final double preco3;
  final double precoCusto;
  final double custoMedio;
  final int estoque;
  final int quantidadeMinima;
  final String unidade;
  final String marca;
  final String fabricante;
  final String codigoBarras;
  final String ncm;
  final String familia;
  final String grupo;
  final String subgrupo;
  final bool ativo;
  final String subcategoriaFallback;

  /// Quando true (ex.: JSON Chacal sem estoque), nao zera estoque de produtos ja cadastrados.
  final bool manterEstoqueAoAtualizar;

  double get precoVenda {
    if (preco1 > 0) return preco1;
    if (preco2 > 0) return preco2;
    if (preco3 > 0) return preco3;
    if (precoCusto > 0) return precoCusto;
    return 0.01;
  }

  CategoriaImportacaoResult get categoriaResolvida =>
      CategoriaImportacaoMapper.resolver(
        familia: familia,
        grupo: grupo,
        subgrupo: subgrupo,
        subcategoriaFallback: subcategoriaFallback,
      );

  Produto paraProduto({Produto? existente}) {
    final cat = categoriaResolvida;
    final precoV = precoVenda;
    var preco2Imp = preco2 > 0 ? preco2 : (existente?.preco2 ?? 0);
    var preco3Imp = preco3 > 0 ? preco3 : (existente?.preco3 ?? 0);

    if (existente != null && preco2 <= 0 && preco3 <= 0) {
      final p1a = existente.preco1;
      if (p1a > 0 &&
          (existente.preco2 - p1a).abs() < 0.0001 &&
          (existente.preco3 - p1a).abs() < 0.0001) {
        preco2Imp = 0;
        preco3Imp = 0;
      }
    }

    final custoMedioVal = custoMedio > 0
        ? custoMedio
        : (existente?.custoMedio ?? 0);

    return Produto(
      id: existente?.id ?? 0,
      codigoInterno: codigoInterno,
      nome: ProdutoImportacaoUtil.normalizarNome(nome),
      descricao: descricao.trim(),
      unidade: ProdutoEmbalagem.normalizarUnidade(
        unidade.trim().isEmpty ? 'UN' : unidade,
      ),
      categoria: cat.categoria,
      subcategoria: cat.subcategoria,
      marca: marca.trim(),
      fornecedor: existente?.fornecedor ?? '',
      fabricante: fabricante.trim().isNotEmpty
          ? fabricante.trim()
          : (existente?.fabricante ?? ''),
      codigoBarras: codigoBarras,
      fotoPath: existente?.fotoPath ?? '',
      localizacao: existente?.localizacao ?? '',
      ncm: ncm,
      estoque: (existente != null && manterEstoqueAoAtualizar)
          ? existente.estoqueReal
          : estoque,
      quantidadeMinima: quantidadeMinima > 0
          ? quantidadeMinima
          : (existente?.quantidadeMinima ?? 0),
      precoCusto: precoCusto,
      custoMedio: custoMedioVal,
      preco1: precoV,
      preco2: preco2Imp,
      preco3: preco3Imp,
      precoVenda: precoV,
      criadoEm: existente?.criadoEm,
      ativo: ativo,
    );
  }
}

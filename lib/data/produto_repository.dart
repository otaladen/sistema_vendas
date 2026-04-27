import '../model/produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

class ProdutoRepository {
  ProdutoRepository(this._db);

  final ObjectBox _db;
  static const List<String> _unidadesValidas = ['UN', 'M', 'M2', 'M3', 'KG', 'SC', 'CX', 'LT'];

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

  List<Produto> pesquisar(String termo) {
    final termoNormalizado = termo.trim().toLowerCase();
    if (termoNormalizado.isEmpty) {
      return listarTodos();
    }
    return listarTodos().where((produto) {
      final campos = [
        produto.nome,
        produto.codigoInterno,
        produto.categoria,
        produto.marca,
        produto.fornecedor,
        produto.fabricante,
        produto.codigoBarras,
      ].map((e) => e.toLowerCase());
      return campos.any((campo) => campo.contains(termoNormalizado));
    }).toList();
  }

  int salvar(Produto produto) => _db.produtoBox.put(produto);

  bool remover(int id) => _db.produtoBox.remove(id);

  Produto? obterPorId(int id) => _db.produtoBox.get(id);
}

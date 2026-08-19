import '../model/item_inventario.dart';
import '../model/produto.dart';
import '../model/sessao_inventario.dart';
import '../domain/inventario_codec.dart';

/// Contrato do balanco: ObjectBox no PC1 ou LAN API no terminal.
abstract class InventarioGateway {
  Future<List<SessaoInventario>> listarSessoes();

  Future<SessaoInventario?> obterSessao(int id);

  Future<InventarioCategoriasInfo> obterCategorias();

  Future<int> contarProdutosNoFiltro({
    String categoria = '',
    String subcategoria = '',
  });

  Future<SessaoInventario> criarSessao({
    required String nome,
    String categoria = '',
    String subcategoria = '',
    bool contagemCega = false,
    String criadoPor = '',
  });

  Future<SessaoInventario> definirContagemCega({
    required int sessaoId,
    required bool contagemCega,
  });

  Future<List<ItemInventario>> listarItens(
    int sessaoId, {
    String filtro = 'todos',
    String busca = '',
  });

  Future<ItemInventario> registrarContagem({
    required int sessaoId,
    required int itemId,
    required int quantidadeArmazenada,
    String usuarioLogin = '',
  });

  Future<InventarioAplicacaoResultado> aplicarAjustes({
    required int sessaoId,
    String usuarioLogin = '',
  });

  Future<SessaoInventario> cancelarSessao({
    required int sessaoId,
    String usuarioLogin = '',
  });

  Produto? produtoDe(ItemInventario item);
}

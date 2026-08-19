import '../../domain/inventario_codec.dart';
import '../../domain/inventario_contagem.dart';
import '../../model/item_inventario.dart';
import '../../model/produto.dart';
import '../../model/sessao_inventario.dart';
import '../inventario_gateway.dart';
import 'lan_api_client.dart';

/// Balanco no terminal leve: leitura/gravacao no PC1 via LAN API.
class InventarioApiRepository implements InventarioGateway {
  InventarioApiRepository(this._client, {this.produtoRepository});

  final LanApiClient _client;
  final dynamic produtoRepository;

  @override
  Future<List<SessaoInventario>> listarSessoes() async {
    final m = await _client.listarSessoesInventario();
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<SessaoInventario?> obterSessao(int id) async {
    if (id <= 0) return null;
    final m = await _client.obterSessaoInventario(id);
    final sessao = m['sessao'];
    if (sessao is! Map) return null;
    return InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(sessao));
  }

  @override
  Future<InventarioCategoriasInfo> obterCategorias() async {
    final m = await _client.obterCategoriasInventario();
    return InventarioCategoriasInfo.fromMap(m);
  }

  @override
  Future<int> contarProdutosNoFiltro({
    String categoria = '',
    String subcategoria = '',
  }) async {
    final m = await _client.contarProdutosInventario(
      categoria: categoria,
      subcategoria: subcategoria,
    );
    return (m['total'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<SessaoInventario> criarSessao({
    required String nome,
    String categoria = '',
    String subcategoria = '',
    bool contagemCega = false,
    String criadoPor = '',
  }) async {
    final m = await _client.criarSessaoInventario({
      'nome': nome,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'contagemCega': contagemCega,
      'usuarioLogin': criadoPor,
      'criadoPor': criadoPor,
    });
    final sessao = m['sessao'];
    if (sessao is! Map) {
      throw StateError('Sessao de inventario nao retornada pela API.');
    }
    return InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(sessao));
  }

  @override
  Future<SessaoInventario> definirContagemCega({
    required int sessaoId,
    required bool contagemCega,
  }) async {
    final m = await _client.definirContagemCegaInventario(
      sessaoId,
      contagemCega,
    );
    final sessao = m['sessao'];
    if (sessao is! Map) {
      throw StateError('Sessao de inventario nao retornada pela API.');
    }
    return InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(sessao));
  }

  @override
  Future<List<ItemInventario>> listarItens(
    int sessaoId, {
    String filtro = 'todos',
    String busca = '',
  }) async {
    final m = await _client.listarItensInventario(
      sessaoId,
      filtro: filtro,
      busca: busca,
    );
    final list = m['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => InventarioCodec.itemDeMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<ItemInventario> registrarContagem({
    required int sessaoId,
    required int itemId,
    required int quantidadeArmazenada,
    String usuarioLogin = '',
  }) async {
    final m = await _client.contarItemInventario(
      sessaoId,
      itemId: itemId,
      quantidadeArmazenada: quantidadeArmazenada,
      usuarioLogin: usuarioLogin,
    );
    final item = m['item'];
    if (item is! Map) {
      throw StateError('Item de inventario nao retornado pela API.');
    }
    return InventarioCodec.itemDeMap(Map<String, dynamic>.from(item));
  }

  @override
  Future<InventarioAplicacaoResultado> aplicarAjustes({
    required int sessaoId,
    String usuarioLogin = '',
  }) async {
    final m = await _client.aplicarInventario(
      sessaoId,
      usuarioLogin: usuarioLogin,
    );
    return InventarioAplicacaoResultado.fromMap(m);
  }

  @override
  Future<SessaoInventario> cancelarSessao({
    required int sessaoId,
    String usuarioLogin = '',
  }) async {
    final m = await _client.cancelarInventario(
      sessaoId,
      usuarioLogin: usuarioLogin,
    );
    final sessao = m['sessao'];
    if (sessao is! Map) {
      throw StateError('Sessao de inventario nao retornada pela API.');
    }
    return InventarioCodec.sessaoDeMap(Map<String, dynamic>.from(sessao));
  }

  @override
  Produto? produtoDe(ItemInventario item) {
    if (item.produtoId <= 0) return null;
    try {
      return produtoRepository?.obterPorId(item.produtoId) as Produto?;
    } catch (_) {
      return InventarioContagem.contextoProduto(item, null);
    }
  }
}

import '../../domain/lista_compra_item_constantes.dart';
import '../../model/item_lista_compra.dart';
import '../../model/produto.dart';
import '../lista_compra_repository.dart';
import 'lan_api_client.dart';

/// Lista de compras do PC servidor, mantida em cache para o terminal leve.
class ListaCompraApiRepository {
  ListaCompraApiRepository(this._client, {this.produtoRepository});

  final LanApiClient _client;
  final dynamic produtoRepository;
  List<ItemListaCompra> _itens = [];

  Future<void> hidratar() async {
    _itens = (await _client.listarListaCompra()).map(_deMap).toList();
  }

  ItemListaCompra _deMap(Map<String, dynamic> m) {
    final item = ItemListaCompra(
      id: (m['id'] as num?)?.toInt() ?? 0,
      descricaoLivre: (m['descricaoLivre'] ?? '').toString(),
      quantidadeSugerida: (m['quantidadeSugerida'] as num?)?.toInt() ?? 1,
      quantidadeRecebida: (m['quantidadeRecebida'] as num?)?.toInt() ?? 0,
      unidade: (m['unidade'] ?? 'UN').toString(),
      fornecedorTexto: (m['fornecedorTexto'] ?? '').toString(),
      prioridade: (m['prioridade'] ?? ListaCompraItemPrioridade.normal)
          .toString(),
      observacao: (m['observacao'] ?? '').toString(),
      origem: (m['origem'] ?? ListaCompraItemOrigem.manual).toString(),
      status: (m['status'] ?? ListaCompraItemStatus.pendente).toString(),
      criadoPor: (m['criadoPor'] ?? '').toString(),
      criadoEm:
          DateTime.tryParse((m['criadoEm'] ?? '').toString()) ?? DateTime.now(),
      resolvidoEm: DateTime.tryParse((m['resolvidoEm'] ?? '').toString()),
      nfeChaveResolucao: (m['nfeChaveResolucao'] ?? '').toString(),
    );
    item.produto.targetId = (m['produtoId'] as num?)?.toInt() ?? 0;
    return item;
  }

  List<ItemListaCompra> listarTodos() => List.unmodifiable(_itens);
  List<ItemListaCompra> listarAtivos() => _itens.where((i) => i.ativo).toList();
  Produto? produtoDe(ItemListaCompra item) =>
      produtoRepository?.obterPorId(item.produtoId);
  int contarAtivos({bool apenasUrgentes = false}) => listarAtivos()
      .where(
        (i) =>
            !apenasUrgentes ||
            i.prioridade == ListaCompraItemPrioridade.urgente,
      )
      .length;
  int contarPorStatus(String status) =>
      _itens.where((i) => i.status == status).length;
  int contarParaLimpeza({Set<String>? statuses, int? maisAntigosQueDias}) => 0;
  List<ListaCompraGrupoFornecedor> agruparAtivosPorFornecedor() => const [];
  Future<List> listarSugestoesSistemaFiltradas() async => const [];
  Future<void> ignorarSugestaoSistema(int produtoId) async {}

  Future<ItemListaCompra> anotar({
    Produto? produto,
    String descricaoLivre = '',
    required int quantidadeSugerida,
    String unidade = 'UN',
    String fornecedorTexto = '',
    String prioridade = ListaCompraItemPrioridade.normal,
    String observacao = '',
    String origem = ListaCompraItemOrigem.manual,
    String criadoPor = '',
  }) async {
    final r = await _client.salvarListaCompra({
      'item': {
        'produtoId': produto?.id ?? 0,
        'descricaoLivre': descricaoLivre,
        'quantidadeSugerida': quantidadeSugerida,
        'unidade': unidade,
        'fornecedorTexto': fornecedorTexto,
        'prioridade': prioridade,
        'observacao': observacao,
        'origem': origem,
        'criadoPor': criadoPor,
      },
    });
    await hidratar();
    final id = (r['id'] as num?)?.toInt() ?? 0;
    for (final i in _itens) {
      if (i.id == id) return i;
    }
    if (_itens.isNotEmpty) return _itens.first;
    throw StateError('Lista de compra: item nao retornado pela API.');
  }
}

import '../../domain/lista_preco_externa.dart';
import '../lista_preco_externa_repository.dart';
import 'lan_api_client.dart';

/// Listas de preco Itinga/Comprou Levou no PC servidor (cache no terminal).
class ListaPrecoExternaApiRepository implements ListaPrecoExternaStore {
  ListaPrecoExternaApiRepository(this._client);

  final LanApiClient _client;

  List<ListaPrecoExternaResumo> _resumos = const [];
  final Map<String, ListaPrecoExterna> _porId = {};

  Future<void> hidratar({bool carregarMaisRecente = true}) async {
    final raw = await _client.listarListasPrecoExternas();
    final resumos = raw
        .map(ListaPrecoExternaResumo.fromJson)
        .toList()
      ..sort((a, b) => b.importadoEm.compareTo(a.importadoEm));
    _resumos = List.unmodifiable(resumos);
    _porId.removeWhere((id, _) => resumos.every((r) => r.id != id));
    if (carregarMaisRecente && resumos.isNotEmpty) {
      await obterPorId(resumos.first.id);
    }
  }

  @override
  Future<List<ListaPrecoExternaResumo>> listarResumos() async {
    if (_resumos.isEmpty) {
      await hidratar(carregarMaisRecente: false);
    }
    return _resumos;
  }

  @override
  Future<ListaPrecoExterna?> obterPorId(String id) async {
    final chave = id.trim();
    if (chave.isEmpty) return null;
    final cached = _porId[chave];
    if (cached != null) return cached;
    final map = await _client.obterListaPrecoExterna(chave);
    if (map == null) return null;
    final lista = ListaPrecoExterna.fromJson(map);
    _porId[chave] = lista;
    return lista;
  }

  @override
  Future<ListaPrecoExterna?> obterMaisRecente() async {
    final resumos = await listarResumos();
    if (resumos.isEmpty) return null;
    return obterPorId(resumos.first.id);
  }

  @override
  Future<ListaPrecoExterna> importarPdf(
    List<int> bytes, {
    required String arquivoOrigem,
  }) async {
    final m = await _client.importarListaPrecoExternaPdf(
      bytes: bytes,
      arquivoOrigem: arquivoOrigem,
    );
    final item = m['item'];
    if (item is! Map) {
      throw StateError('Servidor nao retornou a lista importada.');
    }
    final lista = ListaPrecoExterna.fromJson(Map<String, dynamic>.from(item));
    _porId[lista.id] = lista;
    await hidratar(carregarMaisRecente: false);
    return lista;
  }

  @override
  Future<void> excluir(String id) async {
    final chave = id.trim();
    if (chave.isEmpty) return;
    await _client.excluirListaPrecoExterna(chave);
    _porId.remove(chave);
    await hidratar(carregarMaisRecente: false);
  }

  /// Invalida cache local (ex.: outro PC importou um PDF novo).
  void invalidarCache() {
    _resumos = const [];
    _porId.clear();
  }
}

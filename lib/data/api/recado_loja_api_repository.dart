import '../../domain/recado_loja_helper.dart';
import '../../model/recado_loja.dart';
import '../../model/usuario_sistema.dart';
import '../sync/sync_entity_codec_operacional.dart';
import 'lan_api_client.dart';

/// Recados da loja via API do PC servidor (cache em memoria).
class RecadoLojaApiRepository {
  RecadoLojaApiRepository(this._client);

  final LanApiClient _client;
  List<RecadoLoja> _itens = [];

  Future<void> hidratar() async {
    final raw = await _client.listarRecados();
    final lista = raw
        .map(SyncEntityCodecOperacional.recadoLojaDeMap)
        .toList()
      ..sort(RecadoLojaHelper.comparar);
    _itens = lista;
  }

  List<RecadoLoja> listarTodos() => List.unmodifiable(_itens);

  List<RecadoLoja> listarAtivosParaUsuario(UsuarioSistema usuario) {
    return listarTodos()
        .where((r) => r.ativo && RecadoLojaHelper.aplicaParaUsuario(r, usuario))
        .toList();
  }

  List<RecadoLoja> listarNaoLidosParaUsuario(UsuarioSistema usuario) {
    final login = usuario.login;
    return listarAtivosParaUsuario(usuario)
        .where((r) => !RecadoLojaHelper.foiLido(r, login))
        .toList();
  }

  int contarNaoLidos(UsuarioSistema usuario) =>
      listarNaoLidosParaUsuario(usuario).length;

  int contarArquivados() => _itens.where((r) => !r.ativo).length;

  Future<RecadoLoja> criar({
    required String texto,
    required String prioridade,
    required String destinoTipo,
    String destinoPerfil = '',
    required String criadoPorLogin,
    required String criadoPorNome,
  }) async {
    final m = await _client.criarRecado({
      'texto': texto,
      'prioridade': prioridade,
      'destinoTipo': destinoTipo,
      'destinoPerfil': destinoPerfil,
      'criadoPorLogin': criadoPorLogin,
      'criadoPorNome': criadoPorNome,
    });
    await hidratar();
    final id = (m['id'] as num?)?.toInt() ?? 0;
    for (final r in _itens) {
      if (r.id == id) return r;
    }
    final item = m['item'];
    if (item is Map) {
      return SyncEntityCodecOperacional.recadoLojaDeMap(
        Map<String, dynamic>.from(item),
      );
    }
    throw StateError('Recado nao retornado pela API.');
  }

  Future<RecadoLoja> marcarLido(int id, String login) async {
    final m = await _client.marcarRecadoLido(id, login: login);
    await hidratar();
    for (final r in _itens) {
      if (r.id == id) return r;
    }
    final item = m['item'];
    if (item is Map) {
      return SyncEntityCodecOperacional.recadoLojaDeMap(
        Map<String, dynamic>.from(item),
      );
    }
    throw StateError('Recado nao encontrado apos marcar lido.');
  }

  Future<RecadoLoja> arquivar(int id) async {
    final m = await _client.arquivarRecado(id);
    await hidratar();
    for (final r in _itens) {
      if (r.id == id) return r;
    }
    final item = m['item'];
    if (item is Map) {
      return SyncEntityCodecOperacional.recadoLojaDeMap(
        Map<String, dynamic>.from(item),
      );
    }
    throw StateError('Recado nao encontrado apos arquivar.');
  }

  Future<int> apagarTodosArquivados() async {
    final m = await _client.apagarRecadosArquivados();
    await hidratar();
    return (m['removidos'] as num?)?.toInt() ?? 0;
  }
}

import '../../model/usuario_sistema.dart';
import '../sync/sync_entity_codec_extras.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

/// Usuarios do PC servidor via API (terminal leve — sem cadastro local).
class UsuarioApiRepository {
  UsuarioApiRepository(this._client);

  final LanApiClient _client;

  static const msgServidorDesatualizado =
      'O PC servidor esta com versao antiga da API (sem login remoto).\n\n'
      'No PC 1: feche o Sistema de Vendas por completo (incluindo se estiver '
      'só na bandeja) e abra de novo. Depois tente entrar neste terminal.';

  List<UsuarioSistema> _cache = const [];
  bool _hidratado = false;

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  bool _ehRotaAusente(Object e) {
    final m = '$e'.toLowerCase();
    return m.contains('404') || m.contains('route not found');
  }

  /// Lista completa de usuarios do PC1 (com cache em memoria).
  Future<List<UsuarioSistema>> listarTodos({bool forcar = false}) async {
    _exigirOnline();
    if (_hidratado && !forcar) {
      return List<UsuarioSistema>.from(_cache);
    }
    try {
      final m = await _client.listarUsuarios();
      _cache = SyncEntityCodecExtras.usuariosDeMap(m);
      _hidratado = true;
      return List<UsuarioSistema>.from(_cache);
    } on LanApiException catch (e) {
      if (_ehRotaAusente(e)) {
        // Fallback legado: so status (login ainda funciona).
        final st = await _client.authStatus();
        if (st['temUsuarios'] == true) {
          return [
            const UsuarioSistema(
              id: '_remoto',
              nome: 'Servidor',
              login: '_',
              senha: '',
            ),
          ];
        }
        return [];
      }
      rethrow;
    }
  }

  Future<UsuarioSistema?> obterPorId(String id) async {
    final alvo = id.trim();
    if (alvo.isEmpty) return null;
    for (final u in await listarTodos()) {
      if (u.id == alvo) return u;
    }
    return null;
  }

  Future<UsuarioSistema?> autenticar(String login, String senha) async {
    _exigirOnline();
    try {
      final m = await _client.authLogin(login: login, senha: senha);
      if (m == null) return null;
      final item = m['usuario'];
      if (item is! Map) return null;
      final map = Map<String, dynamic>.from(item);
      map.putIfAbsent('senha', () => '');
      final u = UsuarioSistema.fromMap(map);
      // Atualiza cache se ja hidratado.
      if (_hidratado) {
        final i = _cache.indexWhere((x) => x.id == u.id);
        if (i >= 0) {
          _cache = [..._cache]..[i] = u;
        } else {
          _cache = [..._cache, u];
        }
      }
      return u;
    } on LanApiException catch (e) {
      if (_ehRotaAusente(e)) {
        throw LanApiException(msgServidorDesatualizado, cause: e);
      }
      rethrow;
    }
  }

  Future<bool> loginJaExiste(String login, {String? ignorarId}) async {
    final l = login.trim().toLowerCase();
    if (l.isEmpty) return false;
    final lista = await listarTodos();
    return lista.any((u) {
      if (ignorarId != null && u.id == ignorarId) return false;
      return u.login.trim().toLowerCase() == l;
    });
  }

  Future<void> salvar(
    UsuarioSistema usuario, {
    Object? alteradoPor,
    Object? anterior,
    String? senhaPlainNova,
    String resumoExtra = '',
  }) async {
    await salvarRemoto(
      usuario,
      alteradoPor: alteradoPor is UsuarioSistema ? alteradoPor : null,
      senhaPlainNova: senhaPlainNova,
      resumoExtra: resumoExtra,
    );
  }

  Future<void> salvarRemoto(
    UsuarioSistema usuario, {
    UsuarioSistema? alteradoPor,
    String? senhaPlainNova,
    String resumoExtra = '',
  }) async {
    _exigirOnline();
    final m = await _client.salvarUsuario(
      usuario: usuario.toMapParaSync(),
      senhaPlainNova: senhaPlainNova,
      alteradoPorLogin: alteradoPor?.login ?? '',
      resumoExtra: resumoExtra,
    );
    final item = m['usuario'];
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      map.putIfAbsent('senha', () => '');
      final salvo = UsuarioSistema.fromMap(map);
      final i = _cache.indexWhere((x) => x.id == salvo.id);
      if (i >= 0) {
        _cache = [..._cache]..[i] = salvo;
      } else {
        _cache = [..._cache, salvo];
      }
      _hidratado = true;
    } else {
      await listarTodos(forcar: true);
    }
  }

  Future<void> remover({
    required String id,
    Object? removidoPor,
  }) async {
    await removerRemoto(
      id: id,
      removidoPor: removidoPor is UsuarioSistema ? removidoPor : null,
    );
  }

  Future<void> removerRemoto({
    required String id,
    UsuarioSistema? removidoPor,
  }) async {
    _exigirOnline();
    await _client.removerUsuario(
      id: id,
      removidoPorLogin: removidoPor?.login ?? '',
    );
    _cache = _cache.where((u) => u.id != id).toList();
  }

  Future<int> contarAtivosComVendedorVinculado() async {
    final lista = await listarTodos();
    return lista.where((u) => u.ativo && u.vendedorId > 0).length;
  }

  Future<UsuarioSistema?> obterAtivoPorVendedorId(int vendedorId) async {
    if (vendedorId <= 0) return null;
    final lista = await listarTodos();
    for (final u in lista) {
      if (u.ativo && u.vendedorId == vendedorId) return u;
    }
    return null;
  }

  Future<UsuarioSistema?> autenticarComVendedorVinculado(
    String login,
    String senha, {
    required bool Function(int vendedorId) vendedorAtivo,
  }) async {
    final usuario = await autenticar(login, senha);
    if (usuario == null || usuario.vendedorId <= 0) return null;
    if (!vendedorAtivo(usuario.vendedorId)) return null;
    return usuario;
  }

  void limparCache() {
    _cache = const [];
    _hidratado = false;
  }
}

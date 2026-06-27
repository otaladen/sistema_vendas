import '../domain/recado_loja_constantes.dart';
import '../domain/recado_loja_helper.dart';
import '../model/recado_loja.dart';
import '../model/usuario_sistema.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// CRUD e regras dos recados internos da loja.
class RecadoLojaRepository {
  RecadoLojaRepository(this._db);

  final ObjectBox _db;

  Box<RecadoLoja> get _box => _db.recadoLojaBox;

  List<RecadoLoja> listarTodos() {
    final itens = _box.getAll();
    itens.sort(RecadoLojaHelper.comparar);
    return itens;
  }

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

  RecadoLoja criar({
    required String texto,
    required String prioridade,
    required String destinoTipo,
    String destinoPerfil = '',
    required String criadoPorLogin,
    required String criadoPorNome,
  }) {
    final msg = texto.trim();
    if (msg.isEmpty) {
      throw ArgumentError('Informe o texto do recado.');
    }
    if (!RecadoLojaPrioridade.todos.contains(prioridade)) {
      throw ArgumentError('Prioridade invalida.');
    }
    if (destinoTipo == RecadoLojaDestino.perfil &&
        destinoPerfil.trim().isEmpty) {
      throw ArgumentError('Selecione o perfil de destino.');
    }

    final recado = RecadoLoja(
      texto: msg,
      prioridade: prioridade,
      destinoTipo: destinoTipo,
      destinoPerfil: destinoTipo == RecadoLojaDestino.perfil
          ? destinoPerfil.trim().toLowerCase()
          : '',
      criadoPorLogin: criadoPorLogin.trim(),
      criadoPorNome: criadoPorNome.trim(),
    );
    final id = _box.put(recado);
    recado.id = id;
    _notificar(id);
    return recado;
  }

  RecadoLoja marcarLido(int id, String login) {
    final recado = _obterOuFalhar(id);
    final lg = login.trim().toLowerCase();
    if (lg.isEmpty) {
      throw ArgumentError('Login invalido.');
    }
    if (RecadoLojaHelper.foiLido(recado, lg)) return recado;

    final leituras = RecadoLojaHelper.parseLeituras(recado.leiturasJson);
    leituras.add(lg);
    recado.leiturasJson = RecadoLojaHelper.serializarLeituras(leituras);
    _box.put(recado);
    _notificar(id);
    return recado;
  }

  RecadoLoja arquivar(int id) {
    final recado = _obterOuFalhar(id);
    recado.ativo = false;
    _box.put(recado);
    _notificar(id);
    return recado;
  }

  int contarArquivados() =>
      _box.getAll().where((r) => !r.ativo).length;

  /// Remove permanentemente um recado (sync delete).
  void remover(int id) {
    if (id <= 0 || !_box.contains(id)) return;
    _box.remove(id);
    registrarDeleteParaRede('recado_loja', id);
  }

  /// Apaga todos os recados arquivados. Retorna quantidade removida.
  int apagarTodosArquivados() {
    final ids = _box
        .getAll()
        .where((r) => !r.ativo)
        .map((r) => r.id)
        .where((id) => id > 0)
        .toList();
    for (final id in ids) {
      remover(id);
    }
    return ids.length;
  }

  RecadoLoja _obterOuFalhar(int id) {
    final recado = id > 0 ? _box.get(id) : null;
    if (recado == null) {
      throw StateError('Recado nao encontrado.');
    }
    return recado;
  }

  void _notificar(int id) {
    notificarAlteracaoParaRede(entidade: 'recado_loja', entidadeId: id);
  }
}

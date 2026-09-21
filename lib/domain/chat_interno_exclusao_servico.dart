import '../data/mensagem_interna_repository.dart';
import '../data/usuario_repository.dart';
import '../model/mensagem_interna.dart';
import '../model/usuario_sistema.dart';
import 'chat_interno_exclusao.dart';

abstract final class ChatInternoExclusaoServico {
  ChatInternoExclusaoServico._();

  static Future<UsuarioSistema> _exigirUsuario(
    UsuarioRepository usuarios,
    String login,
  ) async {
    final alvo = login.trim().toLowerCase();
    if (alvo.isEmpty) {
      throw ArgumentError('Login obrigatorio.');
    }
    for (final u in await usuarios.listarTodos()) {
      if (!u.ativo) continue;
      if (u.login.trim().toLowerCase() == alvo) return u;
    }
    throw StateError('Usuario nao encontrado ou inativo.');
  }

  static Future<MensagemInterna?> _buscarPorId(
    MensagemInternaRepository repo,
    int id,
  ) async {
    if (id <= 0) return null;
    final lista = await repo.listarHistorico();
    for (final m in lista) {
      if (m.id == id) return m;
    }
    return null;
  }

  static Future<void> apagar({
    required MensagemInternaRepository repo,
    required UsuarioRepository usuarios,
    required int id,
    required String login,
    required String nomeOperadorLogado,
  }) async {
    final operador = await _exigirUsuario(usuarios, login);
    final msg = await _buscarPorId(repo, id);
    if (msg == null) {
      throw StateError('Mensagem nao encontrada.');
    }
    if (!ChatInternoExclusaoPolitica.podeApagar(
      operador: operador,
      nomeOperadorLogado: nomeOperadorLogado,
      loginOperador: operador.login,
      mensagem: msg,
    )) {
      throw StateError('Voce nao pode apagar esta mensagem.');
    }
    final ok = await repo.apagarPorId(id);
    if (!ok) throw StateError('Mensagem nao encontrada.');
  }

  static Future<List<int>> limparMuralNormais({
    required MensagemInternaRepository repo,
    required UsuarioRepository usuarios,
    required String login,
  }) async {
    final operador = await _exigirUsuario(usuarios, login);
    if (!ChatInternoExclusaoPolitica.ehGerenteOuAdmin(operador)) {
      throw StateError('Somente gerente ou administrador pode limpar o mural.');
    }
    return repo.limparMuralNormais();
  }
}

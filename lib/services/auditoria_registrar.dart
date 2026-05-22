import '../data/auditoria_repository.dart';

/// Ponto unico para registrar eventos de auditoria no app.
class AuditoriaRegistrar {
  AuditoriaRegistrar._();

  static AuditoriaRepository? _repo;
  static String _usuarioSessao = '';

  static void inicializar(AuditoriaRepository repo) {
    _repo = repo;
  }

  static void definirUsuarioSessao(String login) {
    _usuarioSessao = login.trim();
  }

  static void limparUsuarioSessao() {
    _usuarioSessao = '';
  }

  static String get usuarioSessao => _usuarioSessao;

  static void registrar({
    required String modulo,
    required String acao,
    String? usuarioLogin,
    String entidade = '',
    String entidadeId = '',
    String resumo = '',
    Map<String, dynamic>? detalhes,
    DateTime? dataHora,
  }) {
    final repo = _repo;
    if (repo == null) return;
    try {
      repo.registrar(
        modulo: modulo,
        acao: acao,
        usuarioLogin: (usuarioLogin ?? _usuarioSessao).trim(),
        entidade: entidade,
        entidadeId: entidadeId,
        resumo: resumo,
        detalhes: detalhes,
        dataHora: dataHora,
      );
    } catch (_) {
      // Log nao deve impedir operacao principal.
    }
  }
}

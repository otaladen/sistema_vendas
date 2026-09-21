import '../model/mensagem_interna.dart';
import '../model/usuario_sistema.dart';

/// Regras de exclusao do mural interno.
abstract final class ChatInternoExclusaoPolitica {
  ChatInternoExclusaoPolitica._();

  static const janelaOperador = Duration(minutes: 30);

  static bool ehGerenteOuAdmin(UsuarioSistema? operador) {
    if (operador == null || !operador.ativo) return false;
    if (operador.admin) return true;
    final p = operador.perfil.trim().toLowerCase();
    return p == 'gerente' || p == 'dono';
  }

  static bool ehPropria({
    required String nomeOperadorLogado,
    required String loginOperador,
    required MensagemInterna mensagem,
  }) {
    final v = mensagem.vendedor.trim();
    final nome = nomeOperadorLogado.trim();
    if (v.isNotEmpty && nome.isNotEmpty && v == nome) return true;
    final login = loginOperador.trim().toLowerCase();
    if (login.isNotEmpty && v.toLowerCase() == login) return true;
    return false;
  }

  static bool podeApagar({
    required UsuarioSistema? operador,
    required String nomeOperadorLogado,
    required String loginOperador,
    required MensagemInterna mensagem,
    DateTime? agoraUtc,
  }) {
    if (mensagem.preservarNaRetencao) return false;
    if (operador == null || !operador.ativo) return false;

    if (ehGerenteOuAdmin(operador)) return true;

    if (mensagem.pendenteLocal) {
      return ehPropria(
        nomeOperadorLogado: nomeOperadorLogado,
        loginOperador: loginOperador,
        mensagem: mensagem,
      );
    }

    final agora = (agoraUtc ?? DateTime.now()).toUtc();
    if (!ehPropria(
      nomeOperadorLogado: nomeOperadorLogado,
      loginOperador: loginOperador,
      mensagem: mensagem,
    )) {
      return false;
    }
    return agora.difference(mensagem.dataHora.toUtc()) <= janelaOperador;
  }
}

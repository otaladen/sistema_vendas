import '../data/mensagem_interna_repository.dart';
import '../data/usuario_repository.dart';
import '../model/mensagem_interna.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';
import 'auditoria_catalogo.dart';
import 'autorizacao_pdv_chat.dart';

/// Aplica aprovacao/recusa/cancelamento no recado persistido e registra auditoria.
class AutorizacaoPdvChatServico {
  AutorizacaoPdvChatServico._();

  static Future<MensagemInterna> responder({
    required MensagemInternaRepository repo,
    required UsuarioRepository usuarios,
    required String solicitacaoId,
    required String acao,
    required String login,
    String motivo = '',
  }) async {
    final sid = solicitacaoId.trim();
    final loginNorm = login.trim();
    if (sid.isEmpty) {
      throw ArgumentError('solicitacaoId obrigatorio.');
    }
    if (loginNorm.isEmpty) {
      throw ArgumentError('Login do usuario obrigatorio.');
    }
    final msg = await repo.buscarAutorizacaoPdv(sid);
    if (msg == null) {
      throw StateError('Solicitacao de autorizacao nao encontrada.');
    }
    final atual = msg.autorizacaoPdv;
    if (atual == null) {
      throw StateError('Payload de autorizacao invalido.');
    }
    if (!atual.pendente) {
      throw StateError('Esta solicitacao ja foi respondida.');
    }

    final acaoNorm = acao.trim().toLowerCase();
    if (acaoNorm == 'cancelar') {
      if (loginNorm.toLowerCase() != atual.operadorLogin.toLowerCase()) {
        throw StateError('Apenas o operador que solicitou pode cancelar.');
      }
      final novo = atual.copyWith(
        status: AutorizacaoPdvChatStatus.cancelada,
        respondidoPor: loginNorm,
        respondidoEm: DateTime.now().toUtc(),
        motivo: motivo.trim().isEmpty ? 'Cancelado pelo operador' : motivo.trim(),
      );
      return repo.atualizarAutorizacaoPdv(
        solicitacaoId: sid,
        payload: novo,
      );
    }

    final lista = await usuarios.listarTodos();
    UsuarioSistema? aprovador;
    for (final u in lista) {
      if (u.login.trim().toLowerCase() == loginNorm.toLowerCase()) {
        aprovador = u;
        break;
      }
    }
    if (aprovador == null ||
        !usuarioPodeResponderAutorizacaoPdvChat(
          aprovador,
          tipoOperacao: atual.tipoOperacao,
        )) {
      throw StateError(
        'Sem permissao para autorizar no chat. Use um gerente ou administrador.',
      );
    }

    final aprovar = acaoNorm == 'aprovar';
    if (!aprovar && acaoNorm != 'recusar') {
      throw ArgumentError('Acao invalida. Use aprovar, recusar ou cancelar.');
    }
    final novo = atual.copyWith(
      status: aprovar
          ? AutorizacaoPdvChatStatus.aprovada
          : AutorizacaoPdvChatStatus.recusada,
      respondidoPor: aprovador.login,
      respondidoEm: DateTime.now().toUtc(),
      motivo: motivo.trim(),
    );
    final salva = await repo.atualizarAutorizacaoPdv(
      solicitacaoId: sid,
      payload: novo,
    );

    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.orcamento,
      acao: aprovar
          ? AuditoriaAcao.autorizacaoDescontoAcimaTeto
          : AuditoriaAcao.autorizacaoPdvChatRecusada,
      usuarioLogin: aprovador.login,
      entidade: 'autorizacao_pdv_chat',
      entidadeId: sid,
      resumo: aprovar
          ? 'Autorizacao PDV via chat aprovada'
          : 'Autorizacao PDV via chat recusada',
      detalhes: {
        'solicitacaoId': sid,
        'tipoOperacao': atual.tipoOperacao,
        'vendaId': atual.vendaId,
        'carrinhoId': atual.carrinhoId,
        'operador': atual.operadorLogin,
        'valorOriginal': atual.valorOriginal,
        'valorSolicitado': atual.valorSolicitado,
        'descricaoAcao': atual.descricaoAcao,
        'autorizadoPor': aprovador.login,
        'motivo': motivo.trim(),
        'viaChat': true,
        'status': novo.status,
        'quando': novo.respondidoEm?.toIso8601String(),
      },
    );
    return salva;
  }
}

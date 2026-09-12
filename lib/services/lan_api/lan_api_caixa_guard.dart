import 'package:shelf/shelf.dart';

import '../configuracoes_service.dart';
import '../../data/caixa_sessao_repository.dart';
import '../../domain/autorizacao_pdv_chat.dart';
import 'lan_api_deps.dart';
import 'lan_api_json.dart';

String lanApiTerminalIdDaRequisicao(
  Request r, {
  Map<String, dynamic>? body,
}) {
  final doBody = (body?['terminalId'] ?? '').toString().trim();
  if (doBody.isNotEmpty) return doBody;
  final q = (r.url.queryParameters['terminalId'] ?? '').toString().trim();
  if (q.isNotEmpty) return q;
  return (r.headers['x-terminal-id'] ?? '').toString().trim();
}

/// Recusa a operacao se nao houver sessao de caixa aberta (loja ou terminal).
Future<Response?> lanApiExigirCaixaAberto(
  Request r, {
  Map<String, dynamic>? body,
  String mensagem =
      'Nao e possivel finalizar vendas com o caixa fechado.',
}) async {
  final terminalId = lanApiTerminalIdDaRequisicao(r, body: body);
  final repo = CaixaSessaoRepository();
  final config = await ConfiguracoesService.repositoryFallback()
      .carregarEmpresaConfig();
  final mapa = await repo.listarTodasSessoes();
  final sessao = CaixaSessaoRepository.sessaoAbertaPara(
    mapa,
    terminalId: terminalId,
    umCaixaAbertoPorLoja: config.umCaixaAbertoPorLoja,
  );
  if (sessao == null || !sessao.aberto) {
    return lanApiJson(
      {'error': mensagem, 'code': 'caixa_fechado'},
      status: 409,
    );
  }
  return null;
}

/// Valida login/senha de gerente (admin ou financeiro) ou grant do chat interno.
Future<Response?> lanApiExigirGerente(
  LanApiDeps d,
  Map<String, dynamic> body, {
  String mensagem = 'Autorizacao de gerente obrigatoria.',
}) async {
  final grantId = (body['autorizacaoChatId'] ?? '').toString().trim();
  if (grantId.isNotEmpty) {
    final msg = await d.mensagemInternaRepository.buscarAutorizacaoPdv(grantId);
    final payload = msg?.autorizacaoPdv;
    if (payload != null && payload.status == AutorizacaoPdvChatStatus.aprovada) {
      return null;
    }
    return lanApiJson(
      {
        'error': 'Liberacao do chat ausente ou nao aprovada.',
        'code': 'autorizacao_chat_invalida',
      },
      status: 403,
    );
  }
  final login = (body['gerenteLogin'] ?? '').toString().trim();
  final senha = (body['gerenteSenha'] ?? '').toString();
  if (login.isEmpty || senha.isEmpty) {
    return lanApiJson(
      {'error': mensagem, 'code': 'gerente_obrigatorio'},
      status: 403,
    );
  }
  final usuario = await d.usuarioRepository.autenticar(login, senha);
  if (usuario == null ||
      !usuario.ativo ||
      !(usuario.admin || usuario.podeFinanceiro)) {
    return lanApiJson(
      {
        'error': 'Credenciais sem permissao de gerente/financeiro.',
        'code': 'gerente_invalido',
      },
      status: 403,
    );
  }
  return null;
}

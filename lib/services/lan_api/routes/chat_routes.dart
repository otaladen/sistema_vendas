import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/mensagem_interna_repository.dart';
import '../../../domain/autorizacao_pdv_chat.dart';
import '../../../domain/autorizacao_pdv_chat_servico.dart';
import '../../../domain/chat_interno_eventos.dart';
import '../../../domain/chat_interno_exclusao_servico.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void _broadcastChat(
  LanApiDeps d, {
  required Map<String, dynamic> item,
  required int id,
  AutorizacaoPdvChatPayload? autorizacao,
}) {
  d.notificarEvento('novo_recado_chat', {
    'item': item,
    'id': id,
  });
  d.notificar('chat_interno', ids: [id]);
  if (autorizacao != null &&
      AutorizacaoPdvChatStatus.ehFinal(autorizacao.status)) {
    d.notificarEvento(kEventoAutorizacaoPdvResposta, {
      'solicitacaoId': autorizacao.solicitacaoId,
      'status': autorizacao.status,
      'respondidoPor': autorizacao.respondidoPor,
      'motivo': autorizacao.motivo,
      'stationId': autorizacao.stationId,
      'item': item,
    });
  }
}

void registerChatRoutes(Router router, LanApiDeps d) {
  final MensagemInternaRepository repo = d.mensagemInternaRepository;

  router.get('/api/chat/historico', (_) async {
    try {
      final items = await repo.listarHistorico();
      return lanApiJson({
        'items': items.map((m) => m.toMap()).toList(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/chat/enviar', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final payloadRaw = body['payload'];
      Map<String, dynamic>? payload;
      if (payloadRaw is Map) {
        payload = Map<String, dynamic>.from(payloadRaw);
      }
      final mencoesRaw = body['mencoes'];
      List<String>? mencoes;
      if (mencoesRaw is List) {
        mencoes = mencoesRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final criada = await repo.enviar(
        vendedor: (body['vendedor'] ?? '').toString(),
        texto: (body['texto'] ?? '').toString(),
        clientId: (body['clientId'] ?? '').toString(),
        tipo: (body['tipo'] ?? kMensagemInternaTipoTexto).toString(),
        payload: payload,
        mencoes: mencoes,
      );
      final item = criada.toMap();
      _broadcastChat(d, item: item, id: criada.id);
      return lanApiJson({'ok': true, 'id': criada.id, 'item': item});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/chat/apagar', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final idRaw = body['id'];
      final id = idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw') ?? 0;
      final login = (body['login'] ?? '').toString();
      final nome = (body['nomeOperador'] ?? '').toString();
      await ChatInternoExclusaoServico.apagar(
        repo: repo,
        usuarios: d.usuarioRepository,
        id: id,
        login: login,
        nomeOperadorLogado: nome,
      );
      d.notificarEvento(kEventoChatInternoRemovido, {
        'ids': [id],
      });
      d.notificar('chat_interno', ids: [id]);
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/chat/limpar-mural', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final login = (body['login'] ?? '').toString();
      final removidos = await ChatInternoExclusaoServico.limparMuralNormais(
        repo: repo,
        usuarios: d.usuarioRepository,
        login: login,
      );
      d.notificarEvento(kEventoChatInternoLimpo, {
        'ids': removidos,
      });
      d.notificar('chat_interno', ids: removidos);
      return lanApiJson({'ok': true, 'removidos': removidos.length, 'ids': removidos});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/chat/autorizacao/responder', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final atualizada = await AutorizacaoPdvChatServico.responder(
        repo: repo,
        usuarios: d.usuarioRepository,
        solicitacaoId: (body['solicitacaoId'] ?? '').toString(),
        acao: (body['acao'] ?? '').toString(),
        login: (body['login'] ?? '').toString(),
        motivo: (body['motivo'] ?? '').toString(),
      );
      final item = atualizada.toMap();
      _broadcastChat(
        d,
        item: item,
        id: atualizada.id,
        autorizacao: atualizada.autorizacaoPdv,
      );
      return lanApiJson({'ok': true, 'id': atualizada.id, 'item': item});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/mensagem_interna_repository.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

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
      final criada = await repo.enviar(
        vendedor: (body['vendedor'] ?? '').toString(),
        texto: (body['texto'] ?? '').toString(),
        clientId: (body['clientId'] ?? '').toString(),
      );
      final item = criada.toMap();
      d.notificarEvento('novo_recado_chat', {
        'item': item,
        'id': criada.id,
      });
      // Compatibilidade com listeners genericos de entidade.
      d.notificar('chat_interno', ids: [criada.id]);
      return lanApiJson({'ok': true, 'id': criada.id, 'item': item});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}

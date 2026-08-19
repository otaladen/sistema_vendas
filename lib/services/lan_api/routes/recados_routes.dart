import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/recado_loja_repository.dart';
import '../../../data/sync/sync_entity_codec_operacional.dart';
import '../../../data/sync/sync_refresh_hub.dart';
import '../../../model/usuario_sistema.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void _avisarRecadoMudou(LanApiDeps d, {List<int>? ids}) {
  d.notificar('recado_loja', ids: ids);
  try {
    SyncRefreshHub.instance.notificarDadosAtualizados();
  } catch (_) {}
}

void registerRecadosRoutes(Router router, LanApiDeps d) {
  final RecadoLojaRepository repo = d.recadoLojaRepository;

  router.get('/api/recados', (_) {
    return lanApiJson({
      'items': repo
          .listarTodos()
          .map(SyncEntityCodecOperacional.recadoLojaParaMap)
          .toList(),
    });
  });

  router.get('/api/recados/nao-lidos', (Request r) async {
    final login = (r.url.queryParameters['login'] ?? '').trim();
    if (login.isEmpty) {
      return lanApiJson({'error': 'login obrigatorio'}, status: 400);
    }
    final alvo = login.toLowerCase();
    final usuarios = await d.usuarioRepository.listarTodos();
    UsuarioSistema? u;
    for (final x in usuarios) {
      if (x.login.trim().toLowerCase() == alvo) {
        u = x;
        break;
      }
    }
    if (u == null) {
      return lanApiJson({'error': 'usuario nao encontrado'}, status: 404);
    }
    return lanApiJson({
      'items': repo
          .listarNaoLidosParaUsuario(u)
          .map(SyncEntityCodecOperacional.recadoLojaParaMap)
          .toList(),
    });
  });

  // Rotas fixas antes de /<id>/...
  router.post('/api/recados/arquivados/apagar', (Request r) async {
    try {
      final n = repo.apagarTodosArquivados();
      _avisarRecadoMudou(d);
      return lanApiJson({'ok': true, 'removidos': n});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/recados', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final criado = repo.criar(
        texto: (body['texto'] ?? '').toString(),
        prioridade: (body['prioridade'] ?? 'normal').toString(),
        destinoTipo: (body['destinoTipo'] ?? 'todos').toString(),
        destinoPerfil: (body['destinoPerfil'] ?? '').toString(),
        criadoPorLogin: (body['criadoPorLogin'] ?? '').toString(),
        criadoPorNome: (body['criadoPorNome'] ?? '').toString(),
      );
      _avisarRecadoMudou(d, ids: [criado.id]);
      return lanApiJson({
        'ok': true,
        'id': criado.id,
        'item': SyncEntityCodecOperacional.recadoLojaParaMap(criado),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/recados/<id>/lido', (Request r, String idRaw) async {
    final id = int.tryParse(idRaw) ?? 0;
    if (id <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    final body = await lanApiReadJsonMap(r);
    final login = (body?['login'] ?? '').toString().trim();
    if (login.isEmpty) {
      return lanApiJson({'error': 'login obrigatorio'}, status: 400);
    }
    try {
      final atualizado = repo.marcarLido(id, login);
      _avisarRecadoMudou(d, ids: [id]);
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodecOperacional.recadoLojaParaMap(atualizado),
      });
    } on StateError catch (e) {
      return lanApiJson({'error': e.message}, status: 404);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/recados/<id>/arquivar', (Request r, String idRaw) async {
    final id = int.tryParse(idRaw) ?? 0;
    if (id <= 0) {
      return lanApiJson({'error': 'id invalido'}, status: 400);
    }
    try {
      final atualizado = repo.arquivar(id);
      _avisarRecadoMudou(d, ids: [id]);
      return lanApiJson({
        'ok': true,
        'item': SyncEntityCodecOperacional.recadoLojaParaMap(atualizado),
      });
    } on StateError catch (e) {
      return lanApiJson({'error': e.message}, status: 404);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}

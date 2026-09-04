import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../data/lista_preco_externa_repository.dart';
import '../../../data/sync/sync_refresh_hub.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

void _avisarListaPrecoMudou(LanApiDeps d) {
  d.notificar('lista_preco_externa');
  try {
    SyncRefreshHub.instance.notificarDadosAtualizados();
  } catch (_) {}
}

void registerListaPrecoExternaRoutes(Router router, LanApiDeps d) {
  final ListaPrecoExternaRepository repo = d.listaPrecoExternaRepository;

  router.get('/api/listas-preco-externas', (_) async {
    final items = await repo.listarResumos();
    return lanApiJson({
      'items': items.map((e) => e.toJson()).toList(),
    });
  });

  router.get('/api/listas-preco-externas/<id>', (Request _, String id) async {
    final lista = await repo.obterPorId(id.trim());
    if (lista == null) {
      return lanApiJson({'error': 'lista nao encontrada'}, status: 404);
    }
    return lanApiJson({'ok': true, 'item': lista.toJson()});
  });

  router.post('/api/listas-preco-externas/import', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    final b64 = (body['contentBase64'] ?? '').toString().trim();
    if (b64.isEmpty) {
      return lanApiJson({'error': 'contentBase64 obrigatorio'}, status: 400);
    }
    late final List<int> bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return lanApiJson({'error': 'contentBase64 invalido'}, status: 400);
    }
    if (bytes.isEmpty) {
      return lanApiJson({'error': 'PDF vazio'}, status: 400);
    }
    final arquivo = (body['arquivoOrigem'] ?? 'lista.pdf').toString().trim();
    try {
      final lista = await repo.importarPdf(
        bytes,
        arquivoOrigem: arquivo.isEmpty ? 'lista.pdf' : arquivo,
      );
      // importarPdf ja notifica via LanApiServerHub; reforca SyncRefreshHub.
      _avisarListaPrecoMudou(d);
      return lanApiJson({'ok': true, 'id': lista.id, 'item': lista.toJson()});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post(
    '/api/listas-preco-externas/<id>/excluir',
    (Request _, String id) async {
      final chave = id.trim();
      if (chave.isEmpty) {
        return lanApiJson({'error': 'id invalido'}, status: 400);
      }
      try {
        await repo.excluir(chave);
        _avisarListaPrecoMudou(d);
        return lanApiJson({'ok': true, 'id': chave});
      } catch (e) {
        return lanApiJson({'error': '$e'}, status: 400);
      }
    },
  );
}

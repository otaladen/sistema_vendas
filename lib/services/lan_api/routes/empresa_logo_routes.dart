import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../configuracoes_service.dart';
import '../../empresa_logo_service.dart';
import '../lan_api_json.dart';

void registerEmpresaLogoRoutes(
  Router router, {
  required void Function(String entity) notificar,
}) {
  router.get('/api/empresa/logo', (_) async {
    try {
      final bytes = await EmpresaLogoService.lerBytesServidor();
      if (bytes == null) {
        return lanApiJson({'error': 'logo nao configurada'}, status: 404);
      }
      final hash = EmpresaLogoService.hashBytes(bytes);
      return Response.ok(
        bytes,
        headers: {
          'content-type': 'image/png',
          'x-logo-hash': hash,
        },
      );
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.post('/api/empresa/logo', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final repo = ConfiguracoesService.repositoryFallback();
      final atual = await repo.carregarEmpresaConfig();
      final remover = body['remover'] == true;

      if (remover) {
        await EmpresaLogoService.removerServidor();
        final mesclado = atual.copyWith(logoHash: '', logoPath: '');
        await repo.salvarEmpresaConfig(mesclado, propagarRede: true);
        notificar('empresa_config');
        return lanApiJson({'ok': true, 'logoHash': ''});
      }

      final b64 = (body['contentBase64'] ?? '').toString().trim();
      if (b64.isEmpty) {
        return lanApiJson({'error': 'contentBase64 obrigatorio'}, status: 400);
      }
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) {
        return lanApiJson({'error': 'imagem vazia'}, status: 400);
      }
      final gravado = await EmpresaLogoService.gravarServidor(bytes);
      final mesclado = atual.copyWith(
        logoHash: gravado.hash,
        logoPath: gravado.path,
      );
      await repo.salvarEmpresaConfig(mesclado, propagarRede: true);
      notificar('empresa_config');
      return lanApiJson({'ok': true, 'logoHash': gravado.hash});
    } on FormatException {
      return lanApiJson({'error': 'contentBase64 invalido'}, status: 400);
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });
}

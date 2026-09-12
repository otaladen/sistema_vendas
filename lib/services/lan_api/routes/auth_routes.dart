import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../configuracoes_service.dart';
import '../../../data/sync/sync_entity_codec_extras.dart';
import '../../../model/usuario_sistema.dart';
import '../../../services/fiscal_config_store.dart';
import '../lan_api_deps.dart';
import '../lan_api_json.dart';

/// Autenticacao e cadastro de usuarios / config de loja do PC servidor.
void registerAuthRoutes(Router router, LanApiDeps d) {
  router.get('/api/auth/status', (_) async {
    final usuarios = await d.usuarioRepository.listarTodos();
    final ativos = usuarios.where((u) => u.ativo).length;
    return lanApiJson({
      'ok': true,
      'temUsuarios': usuarios.isNotEmpty,
      'total': usuarios.length,
      'ativos': ativos,
    });
  });

  router.post('/api/auth/login', (Request req) async {
    Map<String, dynamic> body;
    try {
      final raw = await req.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return lanApiJson(
          {'ok': false, 'error': 'body_invalido'},
          status: 400,
        );
      }
      body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return lanApiJson({'ok': false, 'error': 'json_invalido'}, status: 400);
    }

    final login = (body['login'] ?? '').toString();
    final senha = (body['senha'] ?? '').toString();
    if (login.trim().isEmpty || senha.isEmpty) {
      return lanApiJson(
        {'ok': false, 'error': 'credenciais_obrigatorias'},
        status: 400,
      );
    }

    final usuario = await d.usuarioRepository.autenticar(login, senha);
    if (usuario == null) {
      return lanApiJson(
        {'ok': false, 'error': 'credenciais_invalidas'},
        status: 401,
      );
    }
    if (!usuario.ativo) {
      return lanApiJson(
        {'ok': false, 'error': 'usuario_inativo'},
        status: 401,
      );
    }

    return lanApiJson({
      'ok': true,
      'usuario': usuario.toMapParaSync(),
    });
  });

  router.get('/api/usuarios', (_) async {
    final usuarios = await d.usuarioRepository.listarTodos();
    return lanApiJson(SyncEntityCodecExtras.usuariosParaMap(usuarios));
  });

  router.post('/api/usuarios/salvar', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final usuarioRaw = body['usuario'];
      if (usuarioRaw is! Map) {
        return lanApiJson({'error': 'usuario obrigatorio'}, status: 400);
      }
      final map = Map<String, dynamic>.from(usuarioRaw);
      map.putIfAbsent('senha', () => '');
      var usuario = UsuarioSistema.fromMap(map);
      if (usuario.id.trim().isEmpty) {
        return lanApiJson({'error': 'id do usuario obrigatorio'}, status: 400);
      }
      UsuarioSistema? anterior;
      for (final u in await d.usuarioRepository.listarTodos()) {
        if (u.id == usuario.id) {
          anterior = u;
          break;
        }
      }
      // Sem hash no payload: preserva senha atual na edicao.
      if ((map['senha'] ?? '').toString().trim().isEmpty && anterior != null) {
        usuario = usuario.copyWith(senha: anterior.senha);
      }
      final senhaPlain = (body['senhaPlainNova'] ?? '').toString();
      final alteradoPorLogin =
          (body['alteradoPorLogin'] ?? '').toString().trim();
      UsuarioSistema? alteradoPor;
      if (alteradoPorLogin.isNotEmpty) {
        for (final u in await d.usuarioRepository.listarTodos()) {
          if (u.login.trim().toLowerCase() == alteradoPorLogin.toLowerCase()) {
            alteradoPor = u;
            break;
          }
        }
      }
      await d.usuarioRepository.salvar(
        usuario,
        alteradoPor: alteradoPor,
        anterior: anterior,
        senhaPlainNova: senhaPlain.isEmpty ? null : senhaPlain,
        resumoExtra: (body['resumoExtra'] ?? '').toString(),
      );
      d.notificar('usuarios_sistema');
      final salvo = await d.usuarioRepository.obterPorId(usuario.id);
      return lanApiJson({
        'ok': true,
        'usuario': (salvo ?? usuario).toMapParaSync(),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.post('/api/usuarios/<id>/remover', (Request r, String id) async {
    final body = await lanApiReadJsonMap(r) ?? <String, dynamic>{};
    try {
      final removidoPorLogin =
          (body['removidoPorLogin'] ?? '').toString().trim();
      UsuarioSistema? removidoPor;
      if (removidoPorLogin.isNotEmpty) {
        for (final u in await d.usuarioRepository.listarTodos()) {
          if (u.login.trim().toLowerCase() == removidoPorLogin.toLowerCase()) {
            removidoPor = u;
            break;
          }
        }
      }
      await d.usuarioRepository.remover(id: id, removidoPor: removidoPor);
      d.notificar('usuarios_sistema');
      return lanApiJson({'ok': true, 'id': id});
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/empresa/config', (_) async {
    try {
      final repo = ConfiguracoesService.repositoryFallback();
      final cfg = await repo.carregarEmpresaConfig();
      return lanApiJson({
        'ok': true,
        'config': SyncEntityCodecExtras.empresaConfigParaMap(cfg),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });

  router.post('/api/empresa/config', (Request r) async {
    final body = await lanApiReadJsonMap(r);
    if (body == null) {
      return lanApiJson({'error': 'JSON invalido'}, status: 400);
    }
    try {
      final raw = body['config'];
      if (raw is! Map) {
        return lanApiJson({'error': 'config obrigatorio'}, status: 400);
      }
      final repo = ConfiguracoesService.repositoryFallback();
      final atual = await repo.carregarEmpresaConfig();
      final mesclado = SyncEntityCodecExtras.empresaConfigDeMap(
        atual,
        Map<String, dynamic>.from(raw),
      );
      await repo.salvarEmpresaConfig(mesclado, propagarRede: true);
      d.notificar('empresa_config');
      return lanApiJson({
        'ok': true,
        'config': SyncEntityCodecExtras.empresaConfigParaMap(mesclado),
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 400);
    }
  });

  router.get('/api/empresa/fiscal', (_) async {
    try {
      final f = await FiscalConfigStore.carregar();
      return lanApiJson({
        'ok': true,
        'fiscal': {
          'apiBaseUrl': f.apiBaseUrl,
          'tokenConfigurado': f.configurado,
          'cnpjEmitente': f.cnpjEmitente,
          'inscricaoEstadualEmitente': f.inscricaoEstadualEmitente,
          'regimeTributarioEmitente': f.regimeTributarioEmitente,
          'ufEmitente': f.ufEmitente,
          'ambiente': f.ambiente,
          'razaoSocialEmitente': f.razaoSocialEmitente,
        },
      });
    } catch (e) {
      return lanApiJson({'error': '$e'}, status: 500);
    }
  });
}

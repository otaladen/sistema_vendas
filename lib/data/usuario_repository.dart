import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auditoria_catalogo.dart';
import '../domain/usuario_auditoria_diff.dart';
import '../domain/usuario_migracao_service.dart';
import '../domain/usuario_permissao_helper.dart';
import '../domain/usuario_senha_codec.dart';
import '../model/usuario_sistema.dart';
import '../services/auditoria_registrar.dart';
import 'sync/sync_write_trigger.dart';

class UsuarioRepository {
  static const _kUsuarios = 'usuarios_sistema_v1';

  Future<List<UsuarioSistema>> listarTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUsuarios);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => UsuarioSistema.fromMap(e.cast<String, dynamic>()))
        .toList();
  }

  Future<UsuarioSistema?> obterPorId(String id) async {
    final alvo = id.trim();
    if (alvo.isEmpty) return null;
    for (final u in await listarTodos()) {
      if (u.id == alvo) return u;
    }
    return null;
  }

  /// Normaliza perfil/senha de todos os usuarios (legado).
  Future<int> migrarTodosLegado({UsuarioSistema? alteradoPor}) async {
    final lista = await listarTodos();
    var n = 0;
    for (var i = 0; i < lista.length; i++) {
      final norm = UsuarioMigracaoService.normalizarLegado(lista[i]);
      if (norm.perfil != lista[i].perfil ||
          norm.senha != lista[i].senha ||
          norm.podeCancelarVendas != lista[i].podeCancelarVendas ||
          norm.podeAcessarPdv != lista[i].podeAcessarPdv) {
        await salvar(
          norm,
          alteradoPor: alteradoPor,
          anterior: lista[i],
          resumoExtra: 'Migracao legado',
        );
        n++;
      }
      lista[i] = norm;
    }
    return n;
  }

  Future<void> salvar(
    UsuarioSistema usuario, {
    UsuarioSistema? alteradoPor,
    UsuarioSistema? anterior,
    String? senhaPlainNova,
    String resumoExtra = '',
  }) async {
    final criacao = anterior == null;
    if (senhaPlainNova != null && senhaPlainNova.isNotEmpty) {
      final erro = PoliticaSenhaUsuario.validar(senhaPlainNova);
      if (erro != null) throw StateError(erro);
    } else if (criacao) {
      throw StateError('Informe a senha do novo usuario.');
    }

    var salvo = usuario;
    if (senhaPlainNova != null && senhaPlainNova.isNotEmpty) {
      salvo = salvo.copyWith(
        senha: UsuarioSenhaCodec.gerarHash(senhaPlainNova.trim()),
      );
    } else if (criacao) {
      salvo = salvo.copyWith(senha: UsuarioSenhaCodec.gerarHash(usuario.senha));
    }

    final lista = await listarTodos();
    final idx = lista.indexWhere((u) => u.id == salvo.id);
    if (idx >= 0) {
      lista[idx] = salvo;
    } else {
      lista.add(salvo);
    }
    await _persistir(lista);
    notificarAlteracaoParaRede(
      entidade: 'usuarios_sistema',
      entidadeId: 1,
    );

    final loginAutor = alteradoPor?.login ?? AuditoriaRegistrar.usuarioSessao;
    final diff = UsuarioAuditoriaDiff.diffPermissoes(anterior, salvo);
    AuditoriaRegistrar.registrar(
      modulo: AuditoriaModulo.sistema,
      acao: criacao ? AuditoriaAcao.usuarioCriado : AuditoriaAcao.usuarioAlterado,
      usuarioLogin: loginAutor,
      entidade: 'usuario',
      entidadeId: salvo.id,
      resumo: [
        if (criacao)
          'Usuario criado: ${salvo.nome} (${salvo.login})'
        else
          'Usuario alterado: ${salvo.nome} (${salvo.login})',
        if (resumoExtra.isNotEmpty) resumoExtra,
      ].join(' — '),
      detalhes: diff,
    );
  }

  Future<void> remover({
    required String id,
    UsuarioSistema? removidoPor,
  }) async {
    final lista = await listarTodos();
    UsuarioSistema? alvo;
    for (final u in lista) {
      if (u.id == id) {
        alvo = u;
        break;
      }
    }
    lista.removeWhere((u) => u.id == id);
    await _persistir(lista);
    notificarAlteracaoParaRede(
      entidade: 'usuarios_sistema',
      entidadeId: 1,
    );

    if (alvo != null) {
      final loginAutor = removidoPor?.login ?? AuditoriaRegistrar.usuarioSessao;
      AuditoriaRegistrar.registrar(
        modulo: AuditoriaModulo.sistema,
        acao: AuditoriaAcao.usuarioRemovido,
        usuarioLogin: loginAutor,
        entidade: 'usuario',
        entidadeId: id,
        resumo: 'Usuario removido: ${alvo.nome} (${alvo.login})',
        detalhes: {'perfil': alvo.perfil, 'ativo': alvo.ativo},
      );
    }
  }

  Future<bool> loginJaExiste(String login, {String? ignorarId}) async {
    final l = login.trim().toLowerCase();
    final lista = await listarTodos();
    return lista.any((u) {
      if (ignorarId != null && u.id == ignorarId) return false;
      return u.login.trim().toLowerCase() == l;
    });
  }

  Future<UsuarioSistema?> autenticar(String login, String senha) async {
    final l = login.trim().toLowerCase();
    final s = senha;
    if (l.isEmpty || s.isEmpty) return null;
    final lista = await listarTodos();
    for (final usuario in lista) {
      if (!usuario.ativo) continue;
      if (usuario.login.trim().toLowerCase() != l) continue;
      if (!UsuarioSenhaCodec.verificar(s, usuario.senha)) continue;

      if (!UsuarioSenhaCodec.isHashArmazenado(usuario.senha)) {
        final atualizado = usuario.copyWith(
          senha: UsuarioSenhaCodec.gerarHash(s),
        );
        await salvar(
          atualizado,
          anterior: usuario,
          resumoExtra: 'Senha migrada para hash',
        );
        return atualizado;
      }
      return usuario;
    }
    return null;
  }

  Future<int> contarAtivosComVendedorVinculado() async {
    final lista = await listarTodos();
    return lista.where((u) => u.ativo && u.vendedorId > 0).length;
  }

  /// Login do sistema com vendedor vinculado ativo (identificacao no PDV).
  Future<UsuarioSistema?> autenticarComVendedorVinculado(
    String login,
    String senha, {
    required bool Function(int vendedorId) vendedorAtivo,
  }) async {
    final usuario = await autenticar(login, senha);
    if (usuario == null || usuario.vendedorId <= 0) return null;
    if (!vendedorAtivo(usuario.vendedorId)) return null;
    return usuario;
  }

  Future<void> _persistir(List<UsuarioSistema> usuarios) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(usuarios.map((u) => u.toMap()).toList());
    await prefs.setString(_kUsuarios, payload);
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/usuario_sistema.dart';

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

  Future<void> salvar(UsuarioSistema usuario) async {
    final lista = await listarTodos();
    final idx = lista.indexWhere((u) => u.id == usuario.id);
    if (idx >= 0) {
      lista[idx] = usuario;
    } else {
      lista.add(usuario);
    }
    await _persistir(lista);
  }

  Future<void> remover(String id) async {
    final lista = await listarTodos();
    lista.removeWhere((u) => u.id == id);
    await _persistir(lista);
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
    final s = senha.trim();
    if (l.isEmpty || s.isEmpty) return null;
    final lista = await listarTodos();
    for (final usuario in lista) {
      if (usuario.login.trim().toLowerCase() == l && usuario.senha == s) {
        return usuario;
      }
    }
    return null;
  }

  Future<void> _persistir(List<UsuarioSistema> usuarios) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(usuarios.map((u) => u.toMap()).toList());
    await prefs.setString(_kUsuarios, payload);
  }
}

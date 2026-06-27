import 'dart:convert';

import '../model/recado_loja.dart';
import '../model/usuario_sistema.dart';
import 'perfil_usuario_preset.dart';
import 'recado_loja_constantes.dart';

/// Regras de visibilidade e leitura dos recados internos.
abstract final class RecadoLojaHelper {
  static List<String> parseLeituras(String json) {
    final raw = json.trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String serializarLeituras(Iterable<String> logins) {
    final lista = logins
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return jsonEncode(lista);
  }

  static String mesclarLeiturasJson(String a, String b) {
    final merged = <String>{
      ...parseLeituras(a),
      ...parseLeituras(b),
    };
    return serializarLeituras(merged);
  }

  static bool foiLido(RecadoLoja recado, String login) {
    final lg = login.trim().toLowerCase();
    if (lg.isEmpty) return false;
    return parseLeituras(recado.leiturasJson).contains(lg);
  }

  static bool aplicaParaUsuario(RecadoLoja recado, UsuarioSistema usuario) {
    if (!recado.ativo) return false;
    if (recado.destinoTipo == RecadoLojaDestino.todos) return true;
    if (recado.destinoTipo != RecadoLojaDestino.perfil) return true;
    final perfilUsuario = perfilUsuarioFromId(usuario.perfil).id;
    final destino = recado.destinoPerfil.trim().toLowerCase();
    if (destino.isEmpty) return true;
    if (perfilUsuario == destino) return true;
    // Gerente e dono veem recados de qualquer perfil.
    if (perfilUsuario == PerfilUsuarioPreset.gerente.id ||
        perfilUsuario == PerfilUsuarioPreset.dono.id) {
      return true;
    }
    return false;
  }

  static bool podeArquivar(RecadoLoja recado, UsuarioSistema usuario) {
    final login = usuario.login.trim().toLowerCase();
    if (login.isNotEmpty &&
        recado.criadoPorLogin.trim().toLowerCase() == login) {
      return true;
    }
    return podeManutencao(usuario);
  }

  /// Gerente, dono ou admin — limpeza do historico arquivado.
  static bool podeManutencao(UsuarioSistema usuario) {
    if (usuario.admin) return true;
    final perfil = perfilUsuarioFromId(usuario.perfil);
    return perfil == PerfilUsuarioPreset.gerente ||
        perfil == PerfilUsuarioPreset.dono;
  }

  static int prioridadeOrdenacao(String prioridade) {
    switch (prioridade) {
      case RecadoLojaPrioridade.urgente:
        return 0;
      case RecadoLojaPrioridade.importante:
        return 1;
      default:
        return 2;
    }
  }

  static int comparar(RecadoLoja a, RecadoLoja b) {
    final pa = prioridadeOrdenacao(a.prioridade);
    final pb = prioridadeOrdenacao(b.prioridade);
    if (pa != pb) return pa.compareTo(pb);
    return b.criadoEm.compareTo(a.criadoEm);
  }
}

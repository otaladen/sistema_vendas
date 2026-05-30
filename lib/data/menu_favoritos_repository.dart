import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/main_menu_destino.dart';

/// Favoritos do menu por usuario (atalhos fixados no dashboard e no rail).
class MenuFavoritosRepository {
  MenuFavoritosRepository._();

  static const maxFavoritos = 4;
  static const _prefixo = 'menu_favoritos_v1_';

  static Future<List<MainMenuDestino>> carregar(String login) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefixo${login.trim().toLowerCase()}');
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map((e) => MainMenuDestino.fromCodigo(e?.toString()))
          .whereType<MainMenuDestino>()
          .where((d) => d != MainMenuDestino.inicio)
          .take(maxFavoritos)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> salvar(
    String login,
    List<MainMenuDestino> favoritos,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final unicos = <MainMenuDestino>[];
    for (final d in favoritos) {
      if (d == MainMenuDestino.inicio) continue;
      if (!unicos.contains(d)) unicos.add(d);
      if (unicos.length >= maxFavoritos) break;
    }
    final key = '$_prefixo${login.trim().toLowerCase()}';
    if (unicos.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode(unicos.map((d) => d.name).toList()),
    );
  }

  static Future<List<MainMenuDestino>> alternar({
    required String login,
    required MainMenuDestino destino,
    required bool podeAcessar,
  }) async {
    if (destino == MainMenuDestino.inicio || !podeAcessar) {
      return carregar(login);
    }
    var atual = await carregar(login);
    if (atual.contains(destino)) {
      atual = atual.where((d) => d != destino).toList();
    } else {
      if (atual.length >= maxFavoritos) {
        atual = [...atual.skip(1), destino];
      } else {
        atual = [...atual, destino];
      }
    }
    await salvar(login, atual);
    return atual;
  }
}

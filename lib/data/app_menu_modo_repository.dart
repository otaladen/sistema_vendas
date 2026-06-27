import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/app_menu_modo_id.dart';

/// Preferencia de modo do menu por maquina e por usuario logado.
class AppMenuModoRepository {
  AppMenuModoRepository._();

  static const _kMaquina = 'app_menu_modo_maquina_v1';
  static const _kUsuarioPrefix = 'app_menu_modo_usuario_v1_';

  static Future<AppMenuModoId> carregar({String? login}) async {
    final prefs = await SharedPreferences.getInstance();
    if (login != null && login.trim().isNotEmpty) {
      final usuario = prefs.getString(_chaveUsuario(login));
      if (usuario != null && usuario.trim().isNotEmpty) {
        return AppMenuModoId.fromCodigo(usuario);
      }
    }
    return AppMenuModoId.fromCodigo(prefs.getString(_kMaquina));
  }

  static Future<void> salvar(
    AppMenuModoId modo, {
    String? login,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMaquina, modo.codigo);
    if (login != null && login.trim().isNotEmpty) {
      await prefs.setString(_chaveUsuario(login), modo.codigo);
    }
  }

  static String _chaveUsuario(String login) =>
      '$_kUsuarioPrefix${login.trim().toLowerCase()}';
}

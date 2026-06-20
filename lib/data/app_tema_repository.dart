import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/app_tema_id.dart';

/// Preferencia de tema por maquina e por usuario logado.
class AppTemaRepository {
  AppTemaRepository._();

  static const _kMaquina = 'app_tema_maquina_v1';
  static const _kUsuarioPrefix = 'app_tema_usuario_v1_';

  static Future<AppTemaId> carregar({String? login}) async {
    final prefs = await SharedPreferences.getInstance();
    if (login != null && login.trim().isNotEmpty) {
      final usuario = prefs.getString(_chaveUsuario(login));
      if (usuario != null && usuario.trim().isNotEmpty) {
        return AppTemaId.fromCodigo(usuario);
      }
    }
    return AppTemaId.fromCodigo(prefs.getString(_kMaquina));
  }

  static Future<void> salvar(
    AppTemaId tema, {
    String? login,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMaquina, tema.codigo);
    if (login != null && login.trim().isNotEmpty) {
      await prefs.setString(_chaveUsuario(login), tema.codigo);
    }
  }

  static String _chaveUsuario(String login) =>
      '$_kUsuarioPrefix${login.trim().toLowerCase()}';
}

import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/app_fundo_id.dart';

/// Preferencia de plano de fundo por maquina e por usuario logado.
class AppFundoRepository {
  AppFundoRepository._();

  static const _kMaquina = 'app_fundo_maquina_v1';
  static const _kUsuarioPrefix = 'app_fundo_usuario_v1_';

  static Future<AppFundoId> carregar({String? login}) async {
    final prefs = await SharedPreferences.getInstance();
    if (login != null && login.trim().isNotEmpty) {
      final usuario = prefs.getString(_chaveUsuario(login));
      if (usuario != null && usuario.trim().isNotEmpty) {
        return AppFundoId.fromCodigo(usuario);
      }
    }
    return AppFundoId.fromCodigo(prefs.getString(_kMaquina));
  }

  static Future<void> salvar(
    AppFundoId fundo, {
    String? login,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMaquina, fundo.codigo);
    if (login != null && login.trim().isNotEmpty) {
      await prefs.setString(_chaveUsuario(login), fundo.codigo);
    }
  }

  static String _chaveUsuario(String login) =>
      '$_kUsuarioPrefix${login.trim().toLowerCase()}';
}

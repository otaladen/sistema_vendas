import 'package:shared_preferences/shared_preferences.dart';

/// Ultimo id de recado visto neste aparelho (badge sobrevive ao restart).
abstract final class ChatInternoLeituraStorage {
  ChatInternoLeituraStorage._();

  static const _k = 'chat_interno_ultimo_id_visto_v1';

  static Future<int> carregar() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_k) ?? 0;
  }

  static Future<void> salvar(int id) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_k, id < 0 ? 0 : id);
  }
}

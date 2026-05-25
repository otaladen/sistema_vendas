import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Resolve a chave da API Gemini sem embutir segredo no codigo-fonte.
abstract final class GeminiConfig {
  static const _kPrefs = 'gemini_api_key_v1';
  static const envDartDefine = 'GEMINI_API_KEY';

  static const String _fromCompile =
      String.fromEnvironment(envDartDefine, defaultValue: '');

  /// Ordem: `--dart-define`, variavel de ambiente do SO, SharedPreferences.
  static Future<String> resolverChave() async {
    final compile = _fromCompile.trim();
    if (compile.isNotEmpty) return compile;

    try {
      final env = Platform.environment[envDartDefine]?.trim() ?? '';
      if (env.isNotEmpty) return env;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPrefs)?.trim() ?? '';
  }

  static Future<void> salvarChave(String chave) async {
    final prefs = await SharedPreferences.getInstance();
    final limpa = chave.trim();
    if (limpa.isEmpty) {
      await prefs.remove(_kPrefs);
    } else {
      await prefs.setString(_kPrefs, limpa);
    }
  }

  static bool chavePareceValida(String chave) => chave.trim().length >= 20;
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Registro de auditoria do caixa (SharedPreferences, mesma chave do modulo Caixa).
class CaixaAuditoriaRegistro {
  CaixaAuditoriaRegistro({
    required this.em,
    required this.evento,
    required this.usuario,
    required this.operadorCaixa,
    required this.detalhes,
  });

  final DateTime em;
  final String evento;
  final String usuario;
  final String operadorCaixa;
  final Map<String, dynamic> detalhes;

  factory CaixaAuditoriaRegistro.fromMap(Map<String, dynamic> map) {
    final emRaw = map['em']?.toString() ?? '';
    DateTime em;
    try {
      em = DateTime.parse(emRaw);
    } catch (_) {
      em = DateTime.now();
    }
    final det = map['detalhes'];
    return CaixaAuditoriaRegistro(
      em: em,
      evento: map['evento']?.toString() ?? '',
      usuario: map['usuario']?.toString() ?? '',
      operadorCaixa: map['operadorCaixa']?.toString() ?? '',
      detalhes: det is Map
          ? det.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
    );
  }

  bool get ehFechamento => evento == 'fechamento_caixa';

  double? get diferencaTotal {
    final v = detalhes['diferencaTotal'];
    if (v is num) return v.toDouble();
    return null;
  }
}

/// Leitura dos eventos de auditoria gravados pelo [CaixaPage].
class CaixaAuditoriaRepository {
  static const String chavePrefs = 'caixa_auditoria_eventos_v1';

  Future<List<CaixaAuditoriaRegistro>> listarTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(chavePrefs);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => CaixaAuditoriaRegistro.fromMap(e.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.em.compareTo(a.em));
    } catch (_) {
      return [];
    }
  }

  Future<List<CaixaAuditoriaRegistro>> listarFechamentos() async {
    return (await listarTodos()).where((r) => r.ehFechamento).toList();
  }

  Future<void> substituirTodos(List<Map<String, dynamic>> registros) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chavePrefs, jsonEncode(registros));
  }
}

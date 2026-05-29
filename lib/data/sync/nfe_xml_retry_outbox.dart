import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Fila local de downloads de XML NF-e (modelo 55) que falharam.
class NfeXmlRetryOutbox {
  NfeXmlRetryOutbox._();

  static const _kKey = 'nfe_xml_retry_outbox_v1';

  static Future<void> registrar({
    required String chaveAcesso,
    required String urlXml,
    bool cancelada = false,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    final id = _id(chave, cancelada);
    lista.removeWhere((e) => e.id == id);
    lista.add(
      NfeXmlRetryItem(
        chaveAcesso: chave,
        urlXml: url,
        cancelada: cancelada,
      ),
    );
    await _gravar(prefs, lista);
  }

  static Future<void> remover({
    required String chaveAcesso,
    bool cancelada = false,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    final id = _id(chave, cancelada);
    if (!lista.any((e) => e.id == id)) return;
    lista.removeWhere((e) => e.id == id);
    await _gravar(prefs, lista);
  }

  static Future<List<NfeXmlRetryItem>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _ler(prefs);
  }

  static String _id(String chave, bool cancelada) =>
      cancelada ? '$chave:cancelada' : chave;

  static List<NfeXmlRetryItem> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => NfeXmlRetryItem.fromMap(Map<String, dynamic>.from(m)))
          .where((e) => e.chaveAcesso.length == 44 && e.urlXml.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    List<NfeXmlRetryItem> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

class NfeXmlRetryItem {
  const NfeXmlRetryItem({
    required this.chaveAcesso,
    required this.urlXml,
    this.cancelada = false,
  });

  final String chaveAcesso;
  final String urlXml;
  final bool cancelada;

  String get id => cancelada ? '$chaveAcesso:cancelada' : chaveAcesso;

  Map<String, dynamic> toMap() => {
        'chaveAcesso': chaveAcesso,
        'urlXml': urlXml,
        'cancelada': cancelada,
      };

  factory NfeXmlRetryItem.fromMap(Map<String, dynamic> m) {
    return NfeXmlRetryItem(
      chaveAcesso:
          (m['chaveAcesso'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
      urlXml: (m['urlXml'] ?? '').toString(),
      cancelada: m['cancelada'] == true,
    );
  }
}

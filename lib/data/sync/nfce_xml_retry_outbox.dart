import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Fila local de downloads de XML NFC-e que falharam (F5).
class NfceXmlRetryOutbox {
  NfceXmlRetryOutbox._();

  static const _kKey = 'nfce_xml_retry_outbox_v1';

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
      NfceXmlRetryItem(
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

  static Future<List<NfceXmlRetryItem>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _ler(prefs);
  }

  static String _id(String chave, bool cancelada) =>
      cancelada ? '$chave:cancelada' : chave;

  static List<NfceXmlRetryItem> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => NfceXmlRetryItem.fromMap(Map<String, dynamic>.from(m)))
          .where((e) => e.chaveAcesso.length == 44 && e.urlXml.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    List<NfceXmlRetryItem> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

class NfceXmlRetryItem {
  const NfceXmlRetryItem({
    required this.chaveAcesso,
    required this.urlXml,
    this.cancelada = false,
  });

  final String chaveAcesso;
  final String urlXml;
  final bool cancelada;

  String get id =>
      cancelada ? '$chaveAcesso:cancelada' : chaveAcesso;

  Map<String, dynamic> toMap() => {
        'chaveAcesso': chaveAcesso,
        'urlXml': urlXml,
        'cancelada': cancelada,
      };

  factory NfceXmlRetryItem.fromMap(Map<String, dynamic> m) {
    return NfceXmlRetryItem(
      chaveAcesso: (m['chaveAcesso'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
      urlXml: (m['urlXml'] ?? '').toString(),
      cancelada: m['cancelada'] == true,
    );
  }
}

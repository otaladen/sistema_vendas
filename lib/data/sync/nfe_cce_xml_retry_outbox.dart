import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Fila local de downloads de XML de CC-e que falharam.
class NfeCceXmlRetryOutbox {
  NfeCceXmlRetryOutbox._();

  static const _kKey = 'nfe_cce_xml_retry_outbox_v1';

  static Future<void> registrar({
    required String chaveAcesso,
    required int numeroSequencia,
    required String urlXml,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    final url = urlXml.trim();
    if (chave.length != 44 || numeroSequencia <= 0 || url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    final id = _id(chave, numeroSequencia);
    lista.removeWhere((e) => e.id == id);
    lista.add(
      NfeCceXmlRetryItem(
        chaveAcesso: chave,
        numeroSequencia: numeroSequencia,
        urlXml: url,
      ),
    );
    await _gravar(prefs, lista);
  }

  static Future<void> remover({
    required String chaveAcesso,
    required int numeroSequencia,
  }) async {
    final chave = chaveAcesso.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44 || numeroSequencia <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final lista = _ler(prefs);
    final id = _id(chave, numeroSequencia);
    if (!lista.any((e) => e.id == id)) return;
    lista.removeWhere((e) => e.id == id);
    await _gravar(prefs, lista);
  }

  static Future<List<NfeCceXmlRetryItem>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return _ler(prefs);
  }

  static String _id(String chave, int seq) => '$chave:cce:$seq';

  static List<NfeCceXmlRetryItem> _ler(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => NfeCceXmlRetryItem.fromMap(Map<String, dynamic>.from(m)))
          .where(
            (e) =>
                e.chaveAcesso.length == 44 &&
                e.numeroSequencia > 0 &&
                e.urlXml.isNotEmpty,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    List<NfeCceXmlRetryItem> lista,
  ) async {
    await prefs.setString(
      _kKey,
      jsonEncode(lista.map((e) => e.toMap()).toList()),
    );
  }
}

class NfeCceXmlRetryItem {
  const NfeCceXmlRetryItem({
    required this.chaveAcesso,
    required this.numeroSequencia,
    required this.urlXml,
  });

  final String chaveAcesso;
  final int numeroSequencia;
  final String urlXml;

  String get id => '$chaveAcesso:cce:$numeroSequencia';

  Map<String, dynamic> toMap() => {
        'chaveAcesso': chaveAcesso,
        'numeroSequencia': numeroSequencia,
        'urlXml': urlXml,
      };

  factory NfeCceXmlRetryItem.fromMap(Map<String, dynamic> m) {
    return NfeCceXmlRetryItem(
      chaveAcesso:
          (m['chaveAcesso'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
      numeroSequencia: ((m['numeroSequencia'] as num?) ?? 0).toInt(),
      urlXml: (m['urlXml'] ?? '').toString(),
    );
  }
}

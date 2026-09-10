import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/fiscal/nfe_recebida.dart';

/// Cache local das NF-e recebidas (Focus) por CNPJ destinatario.
class NfeRecebidasCacheStore {
  NfeRecebidasCacheStore._();

  static const _kVersaoPrefix = 'fiscal_nfe_recebidas_versao_v1_';
  static const _kCachePrefix = 'fiscal_nfe_recebidas_cache_v1_';

  static String _cnpjKey(String cnpj) =>
      cnpj.replaceAll(RegExp(r'\D'), '');

  static Future<int> lerUltimaVersao(String cnpj) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_kVersaoPrefix${_cnpjKey(cnpj)}') ?? 0;
  }

  static Future<void> salvarUltimaVersao(String cnpj, int versao) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_kVersaoPrefix${_cnpjKey(cnpj)}', versao);
  }

  static Future<List<NfeRecebida>> carregar(String cnpj) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kCachePrefix${_cnpjKey(cnpj)}');
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            NfeRecebida.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> salvar(String cnpj, List<NfeRecebida> notas) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode([for (final n in notas) n.toJson()]);
    await prefs.setString('$_kCachePrefix${_cnpjKey(cnpj)}', json);
  }

  /// Mescla lote da API (por chave; maior versao prevalece).
  static List<NfeRecebida> mesclar(
    List<NfeRecebida> atual,
    List<NfeRecebida> novas,
  ) {
    final map = <String, NfeRecebida>{
      for (final n in atual)
        if (n.chaveNfe.isNotEmpty) n.chaveNfe: n,
    };
    for (final n in novas) {
      if (n.chaveNfe.isEmpty) continue;
      final prev = map[n.chaveNfe];
      if (prev == null || n.versao >= prev.versao) {
        map[n.chaveNfe] = n;
      }
    }
    final lista = map.values.toList();
    lista.sort((a, b) {
      final da = a.dataEmissao ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.dataEmissao ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return lista;
  }

  static int maxVersaoNaLista(List<NfeRecebida> notas) {
    var max = 0;
    for (final n in notas) {
      if (n.versao > max) max = n.versao;
    }
    return max;
  }
}

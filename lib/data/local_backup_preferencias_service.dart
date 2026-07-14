import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Exporta e restaura [SharedPreferences] no backup completo.
class LocalBackupPreferenciasService {
  LocalBackupPreferenciasService._();

  static const fileName = 'preferencias_locais.json';
  static const _versao = 1;

  static Future<void> exportarParaPasta(Directory pastaBackup) async {
    final prefs = await SharedPreferences.getInstance();
    final entradas = <String, Map<String, dynamic>>{};
    for (final key in prefs.getKeys()) {
      final valor = prefs.get(key);
      if (valor == null) continue;
      if (valor is String) {
        entradas[key] = {'t': 'string', 'v': valor};
      } else if (valor is int) {
        entradas[key] = {'t': 'int', 'v': valor};
      } else if (valor is double) {
        entradas[key] = {'t': 'double', 'v': valor};
      } else if (valor is bool) {
        entradas[key] = {'t': 'bool', 'v': valor};
      } else if (valor is List<String>) {
        entradas[key] = {'t': 'stringList', 'v': valor};
      }
    }

    final payload = {
      'versao': _versao,
      'exportadoEm': DateTime.now().toUtc().toIso8601String(),
      'chaves': entradas.length,
      'preferencias': entradas,
    };
    final arquivo = File(p.join(pastaBackup.path, fileName));
    await arquivo.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  static Future<bool> importarDaPasta(Directory pastaBackup) async {
    final arquivo = File(p.join(pastaBackup.path, fileName));
    if (!arquivo.existsSync()) return false;

    final map = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    final prefsMap = map['preferencias'];
    if (prefsMap is! Map) return false;

    final prefs = await SharedPreferences.getInstance();
    for (final entry in prefsMap.entries) {
      final key = entry.key.toString();
      if (entry.value is! Map) continue;
      final item = Map<String, dynamic>.from(entry.value as Map);
      final tipo = item['t']?.toString();
      switch (tipo) {
        case 'string':
          await prefs.setString(key, item['v']?.toString() ?? '');
        case 'int':
          final v = item['v'];
          if (v is int) {
            await prefs.setInt(key, v);
          } else if (v is num) {
            await prefs.setInt(key, v.toInt());
          }
        case 'double':
          final v = item['v'];
          if (v is double) {
            await prefs.setDouble(key, v);
          } else if (v is num) {
            await prefs.setDouble(key, v.toDouble());
          }
        case 'bool':
          final v = item['v'];
          if (v is bool) await prefs.setBool(key, v);
        case 'stringList':
          final v = item['v'];
          if (v is List) {
            await prefs.setStringList(
              key,
              v.map((e) => e.toString()).toList(),
            );
          }
      }
    }
    return true;
  }

  static bool existeNaPasta(Directory pastaBackup) =>
      File(p.join(pastaBackup.path, fileName)).existsSync();
}

import 'dart:convert';
import 'dart:isolate';

class LanApiListaItensMeta {
  const LanApiListaItensMeta({
    required this.items,
    required this.total,
    required this.totalValor,
  });

  final List<Map<String, dynamic>> items;
  final int total;
  final double totalValor;
}

/// Decodifica JSON de listas da API fora da UI thread.
Future<List<Map<String, dynamic>>> lanApiDecodificarListaItens(
  String corpoJson,
) async {
  final meta = await lanApiDecodificarListaItensComMeta(corpoJson);
  return meta.items;
}

Future<LanApiListaItensMeta> lanApiDecodificarListaItensComMeta(
  String corpoJson,
) {
  return Isolate.run(() => _decodificarListaItensMetaSync(corpoJson));
}

LanApiListaItensMeta _decodificarListaItensMetaSync(String corpoJson) {
  final decoded = jsonDecode(corpoJson);
  if (decoded is! Map) {
    return const LanApiListaItensMeta(items: [], total: 0, totalValor: 0);
  }
  final raw = decoded['items'];
  final items = raw is! List
      ? const <Map<String, dynamic>>[]
      : raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
  final total = (decoded['total'] as num?)?.toInt() ?? items.length;
  final totalValor = (decoded['totalValor'] as num?)?.toDouble() ?? 0;
  return LanApiListaItensMeta(
    items: items,
    total: total,
    totalValor: totalValor,
  );
}

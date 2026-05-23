import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../model/venda.dart';
import 'romaneio_pdf.dart';

/// Abre Google Maps com rota dirigida entre paradas (origem, waypoints, destino).
Future<bool> abrirMapaRotaParadas(List<Venda> paradasOrdenadas) async {
  final enderecos = paradasOrdenadas
      .map(enderecoExibicaoRomaneio)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (enderecos.isEmpty) return false;
  if (enderecos.length == 1) {
    return _abrirUrlExterna(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(enderecos.first)}',
    );
  }

  final origem = enderecos.first;
  final destino = enderecos.last;
  final intermediarios = enderecos.length > 2
      ? enderecos.sublist(1, enderecos.length - 1)
      : <String>[];

  var url =
      'https://www.google.com/maps/dir/?api=1&travelmode=driving'
      '&origin=${Uri.encodeComponent(origem)}'
      '&destination=${Uri.encodeComponent(destino)}';

  if (intermediarios.isNotEmpty) {
    // Limite pratico de waypoints no Google Maps (~10).
    final waypoints = intermediarios.take(8).join('|');
    url += '&waypoints=${Uri.encodeComponent(waypoints)}';
  }

  return _abrirUrlExterna(url);
}

Future<bool> _abrirUrlExterna(String url) async {
  final uri = Uri.parse(url);
  if (Platform.isWindows) {
    try {
      final r = await Process.run(
        'rundll32',
        ['url.dll,FileProtocolHandler', url],
      );
      if (r.exitCode == 0) return true;
    } catch (_) {
      // segue para launchUrl
    }
  }
  try {
    var ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok) ok = await launchUrl(uri);
    return ok;
  } catch (_) {
    return false;
  }
}

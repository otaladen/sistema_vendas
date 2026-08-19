import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../model/venda.dart';
import 'romaneio_pdf.dart';

/// Abre navegacao ate um endereco (celular: Google Maps / geo; Windows: navegador).
Future<bool> abrirNavegacaoEndereco(String endereco) async {
  final q = endereco.trim();
  if (q.isEmpty) return false;
  final encoded = Uri.encodeComponent(q);
  final candidatos = <String>[];

  if (Platform.isAndroid) {
    candidatos.add('google.navigation:q=$encoded&mode=d');
    candidatos.add('geo:0,0?q=$encoded');
    candidatos.add(
      'https://www.google.com/maps/dir/?api=1&destination=$encoded&travelmode=driving',
    );
  } else if (Platform.isIOS) {
    candidatos.add('comgooglemaps://?daddr=$encoded&directionsmode=driving');
    candidatos.add('https://maps.apple.com/?daddr=$encoded&dirflg=d');
    candidatos.add(
      'https://www.google.com/maps/dir/?api=1&destination=$encoded&travelmode=driving',
    );
  } else {
    candidatos.add(
      'https://www.google.com/maps/dir/?api=1&destination=$encoded&travelmode=driving',
    );
    candidatos.add(
      'https://www.google.com/maps/search/?api=1&query=$encoded',
    );
  }

  for (final url in candidatos) {
    if (await abrirUrlExterna(url)) return true;
  }
  return false;
}

/// Abre Google Maps com rota dirigida entre paradas (origem, waypoints, destino).
Future<bool> abrirMapaRotaParadas(List<Venda> paradasOrdenadas) async {
  final enderecos = paradasOrdenadas
      .map(enderecoExibicaoRomaneio)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (enderecos.isEmpty) return false;
  if (enderecos.length == 1) {
    return abrirNavegacaoEndereco(enderecos.first);
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

  return abrirUrlExterna(url);
}

/// Abre URL no app/navegador padrao. No Windows evita o plugin url_launcher.
Future<bool> abrirUrlExterna(String url) async {
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
    // Celular: app externo (Maps/Waze/WhatsApp). In-app webview parece "nao fazer nada".
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
    }
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    return ok;
  } catch (_) {
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre DANFE/XML da Focus no navegador ou visualizador padrao do SO.
Future<void> abrirUrlDocumentoFiscal(
  BuildContext context,
  String url, {
  String mensagemSeVazio =
      'Link do documento fiscal nao disponivel para esta venda.',
}) async {
  final link = url.trim();
  if (link.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagemSeVazio)),
      );
    }
    return;
  }
  final uri = Uri.tryParse(link);
  if (uri == null || !uri.hasScheme) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link do documento fiscal invalido.')),
      );
    }
    return;
  }

  if (Platform.isWindows) {
    try {
      final r = await Process.run(
        'rundll32',
        ['url.dll,FileProtocolHandler', uri.toString()],
      );
      if (r.exitCode == 0) return;
    } catch (_) {}
  }

  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir o documento: $e')),
      );
    }
  }
}

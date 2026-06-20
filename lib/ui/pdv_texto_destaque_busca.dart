import 'package:flutter/material.dart';

/// Destaca o termo buscado no nome do produto (PDV / consulta).
TextSpan pdvTextoDestaqueBusca({
  required BuildContext context,
  required String texto,
  required String termoBusca,
  required TextStyle estiloBase,
}) {
  final termo = termoBusca.trim().toLowerCase();
  if (termo.isEmpty) {
    return TextSpan(text: texto, style: estiloBase);
  }
  final scheme = Theme.of(context).colorScheme;
  final textoLower = texto.toLowerCase();
  final destaque = estiloBase.copyWith(
    color: scheme.onPrimaryContainer,
    fontWeight: FontWeight.normal,
    backgroundColor: scheme.primaryContainer,
  );
  final spans = <TextSpan>[];
  var cursor = 0;

  while (cursor < texto.length) {
    final indice = textoLower.indexOf(termo, cursor);
    if (indice < 0) {
      spans.add(TextSpan(text: texto.substring(cursor)));
      break;
    }
    if (indice > cursor) {
      spans.add(TextSpan(text: texto.substring(cursor, indice)));
    }
    spans.add(
      TextSpan(
        text: texto.substring(indice, indice + termo.length),
        style: destaque,
      ),
    );
    cursor = indice + termo.length;
  }

  return TextSpan(style: estiloBase, children: spans);
}

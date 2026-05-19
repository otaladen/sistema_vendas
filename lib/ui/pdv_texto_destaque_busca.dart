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
  final textoLower = texto.toLowerCase();
  // Verde forte + fundo claro no trecho buscado; resto do nome usa [estiloBase] sem negrito.
  final destaque = estiloBase.copyWith(
    color: const Color(0xFF0A6B1F),
    fontWeight: FontWeight.normal,
    backgroundColor: const Color(0xFFB8F5C3),
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

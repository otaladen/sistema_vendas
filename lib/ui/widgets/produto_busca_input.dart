import 'package:flutter/material.dart';

/// Textos de ajuda alinhados ao PDV (consulta F4).
const String kProdutoBuscaLabel =
    'Pesquisar (nome, SKU, EAN, medidas, apelidos...)';
const String kProdutoBuscaHelper =
    'Palavras: tubo sod 25 · Trechos: tub%sod%25';

InputDecoration produtoBuscaInputDecoration({
  String? labelText,
  String? hintText,
  String? helperText,
  bool isDense = false,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: labelText ?? kProdutoBuscaLabel,
    hintText: hintText,
    helperText: helperText ?? kProdutoBuscaHelper,
    helperMaxLines: 2,
    prefixIcon: prefixIcon ?? const Icon(Icons.search),
    suffixIcon: suffixIcon,
    isDense: isDense,
    border: const OutlineInputBorder(),
  );
}

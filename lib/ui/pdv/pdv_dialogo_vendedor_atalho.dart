import 'package:flutter/services.dart';

import '../../data/vendedor_repository.dart';
import '../../model/vendedor.dart';

/// Digito de teclado principal ou numerico (0-9).
String? pdvDigitoDeTeclaVendedor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
    return '0';
  }
  if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
    return '1';
  }
  if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
    return '2';
  }
  if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
    return '3';
  }
  if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
    return '4';
  }
  if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
    return '5';
  }
  if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
    return '6';
  }
  if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
    return '7';
  }
  if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
    return '8';
  }
  if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
    return '9';
  }
  return null;
}

/// Resolve vendedor ativo pelo [codigoInterno] (ex.: `3`, `V03` -> 3).
Vendedor? pdvResolverVendedorPorCodigoInterno(
  List<Vendedor> vendedoresAtivos,
  String codigo,
) {
  final c = codigo.trim();
  if (c.isEmpty) return null;
  final alvo = int.tryParse(c);
  Vendedor? unicoPorInt;
  for (final v in vendedoresAtivos) {
    final ci = v.codigoInterno.trim();
    if (ci == c) return v;
    if (alvo != null) {
      final n = VendedorRepository.codigoInternoComoInteiro(ci);
      if (n == alvo) {
        if (unicoPorInt != null) return null;
        unicoPorInt = v;
      }
    }
  }
  return unicoPorInt;
}

/// Teclas do modal "Quem esta vendendo?" (handler global do PDV).
bool pdvProcessarTeclaDialogoVendedor({
  required KeyEvent event,
  required bool buscaPorNomeAtiva,
  required List<Vendedor> vendedoresAtivos,
  required void Function(int vendedorId)? onConfirmarPorCodigo,
  void Function()? onCancelar,
}) {
  if (event is! KeyDownEvent) return false;
  if (!buscaPorNomeAtiva) {
    final digito = pdvDigitoDeTeclaVendedor(event.logicalKey);
    if (digito != null) {
      final v = pdvResolverVendedorPorCodigoInterno(vendedoresAtivos, digito);
      if (v != null && onConfirmarPorCodigo != null) {
        onConfirmarPorCodigo(v.id);
      }
      return true;
    }
  }
  if (event.logicalKey == LogicalKeyboardKey.escape) {
    onCancelar?.call();
    return onCancelar != null;
  }
  return false;
}

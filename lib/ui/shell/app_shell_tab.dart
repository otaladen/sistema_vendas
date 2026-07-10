import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';

/// Aba aberta no shell desktop (navigator proprio preserva pilha interna).
class AppShellTab {
  AppShellTab({
    required this.id,
    required this.titulo,
    required this.destino,
    required this.paginaInicial,
    required this.navigatorKey,
    this.subDestino,
  });

  final String id;
  final String titulo;
  final MainMenuDestino destino;
  final MainMenuSubDestino? subDestino;
  final Widget paginaInicial;
  final GlobalKey<NavigatorState> navigatorKey;

  static String idDe({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
  }) {
    if (sub != null) return 'sub:${sub.name}';
    return 'dest:${destino.name}';
  }

  static String tituloDe({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
  }) {
    if (sub != null) return sub.titulo;
    return destino.titulo;
  }
}

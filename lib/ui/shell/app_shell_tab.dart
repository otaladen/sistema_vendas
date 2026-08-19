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
    this.ehDocumento = false,
  });

  /// Limite suave de abas abertas (estilo ERP desktop).
  static const int maxAbasAbertas = 10;

  final String id;
  final String titulo;
  final MainMenuDestino destino;
  final MainMenuSubDestino? subDestino;
  final Widget paginaInicial;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Documento/orcamento com ID proprio (permite varias abas).
  final bool ehDocumento;

  static String idDe({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
  }) {
    if (sub != null) return 'sub:${sub.name}';
    return 'dest:${destino.name}';
  }

  /// ID estavel para documento (ex.: orcamento #12, venda #357).
  static String idDocumento({
    required String tipo,
    required Object documentoId,
  }) =>
      'doc:$tipo:$documentoId';

  static String tituloDe({
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
  }) {
    if (sub != null) return sub.titulo;
    return destino.titulo;
  }

  static bool idEhDocumento(String id) => id.startsWith('doc:');
}

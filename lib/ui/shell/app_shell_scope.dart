import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';

/// Shell desktop ativo: navegacao lateral com abas persistentes.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.destinoAtual,
    required this.subDestinoAtual,
    required this.favoritos,
    required this.irPara,
    required this.irParaSub,
    required this.alternarFavorito,
    required this.fecharAbaAtual,
    required this.abrirAbaDocumento,
    required super.child,
  });

  final MainMenuDestino destinoAtual;
  final MainMenuSubDestino? subDestinoAtual;
  final List<MainMenuDestino> favoritos;
  final void Function(MainMenuDestino destino, {String? configSecaoInicialId})
      irPara;
  final void Function(MainMenuDestino pai, MainMenuSubDestino sub) irParaSub;
  final Future<void> Function(MainMenuDestino destino) alternarFavorito;
  final VoidCallback fecharAbaAtual;

  /// Abre (ou foca) aba de documento com [documentoId] distinto.
  final void Function({
    required String tipo,
    required Object documentoId,
    required String titulo,
    required MainMenuDestino destino,
    MainMenuSubDestino? sub,
    required Widget pagina,
  }) abrirAbaDocumento;

  static AppShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppShellScope>();
    assert(scope != null, 'AppShellScope nao encontrado');
    return scope!;
  }

  static AppShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShellScope>();
  }

  bool get ativo => true;

  bool ehFavorito(MainMenuDestino d) => favoritos.contains(d);

  @override
  bool updateShouldNotify(AppShellScope oldWidget) {
    return destinoAtual != oldWidget.destinoAtual ||
        subDestinoAtual != oldWidget.subDestinoAtual ||
        favoritos != oldWidget.favoritos;
  }
}

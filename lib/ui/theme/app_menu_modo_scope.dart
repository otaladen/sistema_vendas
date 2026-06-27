import 'package:flutter/material.dart';

import 'app_menu_modo_id.dart';

class AppMenuModoScope extends InheritedWidget {
  const AppMenuModoScope({
    super.key,
    required this.modoAtual,
    required this.definirModo,
    required super.child,
  });

  final AppMenuModoId modoAtual;
  final Future<void> Function(AppMenuModoId modo) definirModo;

  static AppMenuModoScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'AppMenuModoScope nao encontrado na arvore.');
    return scope!;
  }

  static AppMenuModoScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppMenuModoScope>();
  }

  @override
  bool updateShouldNotify(AppMenuModoScope oldWidget) =>
      oldWidget.modoAtual != modoAtual;
}

import 'package:flutter/material.dart';

import 'app_tema_id.dart';

class AppTemaScope extends InheritedWidget {
  const AppTemaScope({
    super.key,
    required this.temaAtual,
    required this.definirTema,
    required super.child,
  });

  final AppTemaId temaAtual;
  final Future<void> Function(AppTemaId tema) definirTema;

  static AppTemaScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'AppTemaScope nao encontrado na arvore.');
    return scope!;
  }

  static AppTemaScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppTemaScope>();
  }

  @override
  bool updateShouldNotify(AppTemaScope oldWidget) =>
      oldWidget.temaAtual != temaAtual;
}

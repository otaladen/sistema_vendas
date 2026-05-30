import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';

/// Shell desktop ativo: navegacao lateral sem empilhar rotas na raiz.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.destinoAtual,
    required this.favoritos,
    required this.irPara,
    required this.alternarFavorito,
    required super.child,
  });

  final MainMenuDestino destinoAtual;
  final List<MainMenuDestino> favoritos;
  final void Function(MainMenuDestino destino) irPara;
  final Future<void> Function(MainMenuDestino destino) alternarFavorito;

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
        favoritos != oldWidget.favoritos;
  }
}

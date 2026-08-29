import 'package:flutter/material.dart';

import 'app_fundo_id.dart';

class AppFundoScope extends InheritedWidget {
  const AppFundoScope({
    super.key,
    required this.fundoAtual,
    required this.definirFundo,
    required super.child,
  });

  final AppFundoId fundoAtual;
  final Future<void> Function(AppFundoId fundo) definirFundo;

  static AppFundoScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'AppFundoScope nao encontrado na arvore.');
    return scope!;
  }

  static AppFundoScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppFundoScope>();
  }

  @override
  bool updateShouldNotify(AppFundoScope oldWidget) =>
      oldWidget.fundoAtual != fundoAtual;
}

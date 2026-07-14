import 'package:flutter/material.dart';

/// Indica se a aba do [IndexedStack] que contem este subarvore esta ativa.
///
/// Telas com timers periodicos (dashboard, Loja ao vivo) devem pausar o trabalho
/// quando [ativa] for false.
class AppShellAbaVisibilidade extends InheritedWidget {
  const AppShellAbaVisibilidade({
    super.key,
    required this.ativa,
    required super.child,
  });

  final bool ativa;

  static bool estaAtiva(BuildContext context) {
    final inherited =
        context.dependOnInheritedWidgetOfExactType<AppShellAbaVisibilidade>();
    return inherited?.ativa ?? true;
  }

  /// Leitura sem registrar dependencia (seguro em callbacks de [Timer]).
  static bool leituraSemDependencia(BuildContext context) {
    final inherited =
        context.getInheritedWidgetOfExactType<AppShellAbaVisibilidade>();
    return inherited?.ativa ?? true;
  }

  @override
  bool updateShouldNotify(AppShellAbaVisibilidade oldWidget) =>
      ativa != oldWidget.ativa;
}

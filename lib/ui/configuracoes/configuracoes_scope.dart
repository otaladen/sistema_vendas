import 'package:flutter/material.dart';

import '../../services/configuracoes_service.dart';

/// Expoe [ConfiguracoesService] na arvore de widgets (padrao InheritedWidget do app).
class ConfiguracoesScope extends InheritedWidget {
  const ConfiguracoesScope({
    super.key,
    required this.service,
    required super.child,
  });

  final ConfiguracoesService service;

  static ConfiguracoesService of(BuildContext context) {
    final service = maybeOf(context);
    assert(service != null, 'ConfiguracoesScope nao encontrado na arvore.');
    return service!;
  }

  static ConfiguracoesService? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ConfiguracoesScope>()
        ?.service;
  }

  @override
  bool updateShouldNotify(ConfiguracoesScope oldWidget) =>
      oldWidget.service != service;
}

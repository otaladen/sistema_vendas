import 'package:flutter/material.dart';

/// Navigator isolado por aba: rotas empilhadas (ex.: conferencia NF-e) sobrevivem ao trocar de aba.
class AppShellTabNavigator extends StatelessWidget {
  const AppShellTabNavigator({
    super.key,
    required this.navigatorKey,
    required this.paginaInicial,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget paginaInicial;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => paginaInicial,
        );
      },
    );
  }
}

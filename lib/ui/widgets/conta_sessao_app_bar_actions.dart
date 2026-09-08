import 'package:flutter/material.dart';

import '../app_global_error_handler.dart';

enum _AcaoMenuConta { mudarUsuario, sair }

/// Login + menu [Mudar de usuário] / [Sair] para AppBars (menu principal, hub Vendas, etc.).
class ContaSessaoAppBarActions extends StatelessWidget {
  const ContaSessaoAppBarActions({
    super.key,
    required this.login,
    required this.onLogout,
  });

  final String login;
  final VoidCallback onLogout;

  /// Espera o [PopupMenu] fechar antes de mexer no navigator / sessao.
  ///
  /// Chamar [Navigator.popUntil] no [onSelected] trava o navigator
  /// (`!_debugLocked`) e o context do menu ja pode estar desativado.
  void _agendarLogout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final navigator = appNavigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      } catch (_) {}
      onLogout();
    });
  }

  Future<void> _confirmarMudarDeUsuario(BuildContext context) async {
    final aceitar = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Mudar de usuário'),
          content: const Text(
            'Voce será desconectado e poderá entrar com outra conta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mudar'),
            ),
          ],
        );
      },
    );
    if (aceitar != true) return;
    _agendarLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
          child: Center(
            child: Text(
              login,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        PopupMenuButton<_AcaoMenuConta>(
          tooltip: 'Conta e sessão',
          icon: const Icon(Icons.account_circle_outlined),
          onSelected: (acao) {
            switch (acao) {
              case _AcaoMenuConta.mudarUsuario:
                _confirmarMudarDeUsuario(context);
                break;
              case _AcaoMenuConta.sair:
                _agendarLogout();
                break;
            }
          },
          itemBuilder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return [
              PopupMenuItem(
                value: _AcaoMenuConta.mudarUsuario,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.switch_account_outlined,
                    color: scheme.primary,
                  ),
                  title: const Text('Mudar de usuário'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _AcaoMenuConta.sair,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.logout,
                    color: scheme.error,
                  ),
                  title: const Text('Sair'),
                ),
              ),
            ];
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

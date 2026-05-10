import 'package:flutter/material.dart';

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

  Future<void> _confirmarMudarDeUsuario(BuildContext context) async {
    final aceitar = await showDialog<bool>(
      context: context,
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
    if (aceitar == true && context.mounted) onLogout();
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
                onLogout();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _AcaoMenuConta.mudarUsuario,
              child: Row(
                children: [
                  Icon(
                    Icons.switch_account_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Mudar de usuário')),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _AcaoMenuConta.sair,
              child: Row(
                children: [
                  Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Sair')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

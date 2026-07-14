import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_modulo_cores.dart';

/// Menu em gaveta (drawer) para layout mobile / tablet estreito.
class AppMenuDrawer extends StatelessWidget {
  const AppMenuDrawer({
    super.key,
    required this.itens,
    required this.destinoAtual,
    required this.subDestinoAtual,
    required this.usuarioLogado,
    required this.onSelecionar,
    required this.onSelecionarSub,
    required this.badgeDe,
    this.badgeSubDe,
  });

  final List<MainMenuDestino> itens;
  final MainMenuDestino destinoAtual;
  final MainMenuSubDestino? subDestinoAtual;
  final UsuarioSistema usuarioLogado;
  final ValueChanged<MainMenuDestino> onSelecionar;
  final void Function(MainMenuDestino pai, MainMenuSubDestino sub)
      onSelecionarSub;
  final int Function(MainMenuDestino destino) badgeDe;
  final int Function(MainMenuSubDestino sub)? badgeSubDe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Menu',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                usuarioLogado.nome.trim().isNotEmpty
                    ? usuarioLogado.nome
                    : usuarioLogado.login,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final d in itens)
                    if (MainMenuSubDestinoHelper.moduloTemSubmenu(d))
                      _GrupoDrawer(
                        destino: d,
                        destinoAtual: destinoAtual,
                        subDestinoAtual: subDestinoAtual,
                        usuarioLogado: usuarioLogado,
                        badge: badgeDe(d),
                        badgeSubDe: badgeSubDe,
                        onSelecionarSub: (sub) => onSelecionarSub(d, sub),
                      )
                    else
                      _ItemDrawer(
                        destino: d,
                        selecionado:
                            d == destinoAtual && subDestinoAtual == null,
                        badge: badgeDe(d),
                        onTap: () => onSelecionar(d),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemDrawer extends StatelessWidget {
  const _ItemDrawer({
    required this.destino,
    required this.selecionado,
    required this.badge,
    required this.onTap,
  });

  final MainMenuDestino destino;
  final bool selecionado;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cor = destino.cor(context);
    return ListTile(
      selected: selecionado,
      leading: Icon(destino.icone, color: cor),
      title: Text(destino.titulo),
      trailing: badge > 0
          ? Badge(label: Text(badge > 99 ? '99+' : '$badge'))
          : null,
      onTap: onTap,
    );
  }
}

class _GrupoDrawer extends StatelessWidget {
  const _GrupoDrawer({
    required this.destino,
    required this.destinoAtual,
    required this.subDestinoAtual,
    required this.usuarioLogado,
    required this.badge,
    this.badgeSubDe,
    required this.onSelecionarSub,
  });

  final MainMenuDestino destino;
  final MainMenuDestino destinoAtual;
  final MainMenuSubDestino? subDestinoAtual;
  final UsuarioSistema usuarioLogado;
  final int badge;
  final int Function(MainMenuSubDestino sub)? badgeSubDe;
  final ValueChanged<MainMenuSubDestino> onSelecionarSub;

  @override
  Widget build(BuildContext context) {
    final subs =
        MainMenuSubDestinoHelper.subitensDe(destino, usuarioLogado);
    final cor = destino.cor(context);
    return ExpansionTile(
      initiallyExpanded: destinoAtual == destino,
      leading: Icon(destino.icone, color: cor),
      title: Row(
        children: [
          Expanded(child: Text(destino.titulo)),
          if (badge > 0)
            Badge(label: Text(badge > 99 ? '99+' : '$badge')),
        ],
      ),
      children: [
        for (final sub in subs)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 56, right: 16),
            selected: destinoAtual == destino && subDestinoAtual == sub,
            title: Text(sub.titulo),
            trailing: () {
              final b = badgeSubDe?.call(sub) ?? 0;
              return b > 0
                  ? Badge(label: Text(b > 99 ? '99+' : '$b'))
                  : null;
            }(),
            onTap: () => onSelecionarSub(sub),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'config_secao.dart';

/// Layout responsivo: rail lateral em telas largas, chips no topo em telas estreitas.
class ConfigPageShell extends StatelessWidget {
  const ConfigPageShell({
    super.key,
    required this.secaoAtual,
    required this.onSecaoChanged,
    required this.child,
  });

  final int secaoAtual;
  final ValueChanged<int> onSecaoChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final secao = ConfigSecoes.todas[secaoAtual.clamp(0, ConfigSecoes.todas.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configuracoes'),
            Text(
              secao.titulo,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final usarRail = constraints.maxWidth >= ConfigSecoes.breakpointRail;
          if (usarRail) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConfigNavigationRail(
                  secaoAtual: secaoAtual,
                  onSecaoChanged: onSecaoChanged,
                  extended: constraints.maxWidth >= 1080,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _ConfigContentArea(child: child)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ConfigSecaoChips(
                secaoAtual: secaoAtual,
                onSecaoChanged: onSecaoChanged,
              ),
              const Divider(height: 1),
              Expanded(child: _ConfigContentArea(child: child)),
            ],
          );
        },
      ),
    );
  }
}

class _ConfigNavigationRail extends StatelessWidget {
  const _ConfigNavigationRail({
    required this.secaoAtual,
    required this.onSecaoChanged,
    required this.extended,
  });

  final int secaoAtual;
  final ValueChanged<int> onSecaoChanged;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NavigationRail(
      extended: extended,
      minExtendedWidth: 220,
      minWidth: 72,
      selectedIndex: secaoAtual,
      onDestinationSelected: onSecaoChanged,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      backgroundColor: scheme.surfaceContainerLow,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Icon(Icons.tune, color: scheme.primary),
      ),
      destinations: [
        for (final s in ConfigSecoes.todas)
          NavigationRailDestination(
            icon: Icon(s.icon),
            selectedIcon: Icon(s.icon, color: scheme.primary),
            label: Text(s.titulo),
          ),
      ],
    );
  }
}

class _ConfigSecaoChips extends StatelessWidget {
  const _ConfigSecaoChips({
    required this.secaoAtual,
    required this.onSecaoChanged,
  });

  final int secaoAtual;
  final ValueChanged<int> onSecaoChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (var i = 0; i < ConfigSecoes.todas.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: Icon(
                    ConfigSecoes.todas[i].icon,
                    size: 18,
                  ),
                  label: Text(ConfigSecoes.todas[i].titulo),
                  selected: secaoAtual == i,
                  onSelected: (_) => onSecaoChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfigContentArea extends StatelessWidget {
  const _ConfigContentArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ConfigSecoes.maxLarguraConteudo,
        ),
        child: child,
      ),
    );
  }
}

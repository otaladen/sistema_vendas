import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../theme/app_menu_modo_estilo.dart';
import '../theme/app_menu_modo_id.dart';
import '../theme/app_modulo_cores.dart';

/// Menu lateral esquerdo do shell desktop (classico ou personalizado).
class AppMenuLateral extends StatelessWidget {
  const AppMenuLateral({
    super.key,
    required this.itens,
    required this.destinoAtual,
    required this.onSelecionar,
    required this.estendido,
    required this.onAlternarEstendido,
    required this.badgeDe,
    this.quantidadeFavoritos = 0,
    this.larguraTela = 1200,
  });

  final List<MainMenuDestino> itens;
  final MainMenuDestino destinoAtual;
  final ValueChanged<MainMenuDestino> onSelecionar;
  final bool estendido;
  final VoidCallback onAlternarEstendido;
  final int Function(MainMenuDestino destino) badgeDe;
  final int quantidadeFavoritos;
  final double larguraTela;

  @override
  Widget build(BuildContext context) {
    if (AppMenuModoEstilo.usaRailPadrao(context)) {
      return _RailClassico(
        itens: itens,
        destinoAtual: destinoAtual,
        onSelecionar: onSelecionar,
        estendido: estendido,
        onAlternarEstendido: onAlternarEstendido,
        badgeDe: badgeDe,
        quantidadeFavoritos: quantidadeFavoritos,
        larguraTela: larguraTela,
      );
    }
    return _RailPersonalizado(
      itens: itens,
      destinoAtual: destinoAtual,
      onSelecionar: onSelecionar,
      estendido: estendido,
      onAlternarEstendido: onAlternarEstendido,
      badgeDe: badgeDe,
      quantidadeFavoritos: quantidadeFavoritos,
      larguraTela: larguraTela,
    );
  }
}

class _RailClassico extends StatelessWidget {
  const _RailClassico({
    required this.itens,
    required this.destinoAtual,
    required this.onSelecionar,
    required this.estendido,
    required this.onAlternarEstendido,
    required this.badgeDe,
    required this.quantidadeFavoritos,
    required this.larguraTela,
  });

  final List<MainMenuDestino> itens;
  final MainMenuDestino destinoAtual;
  final ValueChanged<MainMenuDestino> onSelecionar;
  final bool estendido;
  final VoidCallback onAlternarEstendido;
  final int Function(MainMenuDestino destino) badgeDe;
  final int quantidadeFavoritos;
  final double larguraTela;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final larguraEstendida = larguraTela >= 1200;
    final indice = itens.indexOf(destinoAtual).clamp(0, itens.length - 1);

    return NavigationRail(
      extended: estendido && larguraEstendida,
      minExtendedWidth: 200,
      selectedIndex: indice,
      onDestinationSelected: (i) => onSelecionar(itens[i]),
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: IconButton(
          tooltip: estendido ? 'Recolher menu' : 'Expandir menu',
          onPressed: onAlternarEstendido,
          icon: Icon(
            estendido ? Icons.menu_open_rounded : Icons.menu_rounded,
          ),
        ),
      ),
      labelType: estendido && larguraEstendida
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in itens)
          NavigationRailDestination(
            icon: _iconeComBadge(
              context,
              destino: d,
              selecionado: false,
              badge: badgeDe(d),
            ),
            selectedIcon: _iconeComBadge(
              context,
              destino: d,
              selecionado: true,
              badge: badgeDe(d),
            ),
            label: Text(
              d.titulo,
              style: TextStyle(
                color: d == destinoAtual ? d.cor(context) : null,
                fontWeight:
                    d == destinoAtual ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      trailing: quantidadeFavoritos > 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '$quantidadeFavoritos fav.',
                style: tema.textTheme.labelSmall?.copyWith(
                  color: tema.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }
}

class _RailPersonalizado extends StatelessWidget {
  const _RailPersonalizado({
    required this.itens,
    required this.destinoAtual,
    required this.onSelecionar,
    required this.estendido,
    required this.onAlternarEstendido,
    required this.badgeDe,
    required this.quantidadeFavoritos,
    required this.larguraTela,
  });

  final List<MainMenuDestino> itens;
  final MainMenuDestino destinoAtual;
  final ValueChanged<MainMenuDestino> onSelecionar;
  final bool estendido;
  final VoidCallback onAlternarEstendido;
  final int Function(MainMenuDestino destino) badgeDe;
  final int quantidadeFavoritos;
  final double larguraTela;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estendidoEfetivo = estendido && larguraTela >= 1200;
    final largura = AppMenuModoEstilo.larguraLateralDe(context, estendidoEfetivo);

    return SizedBox(
      width: largura,
      child: DecoratedBox(
        decoration: AppMenuModoEstilo.decoracaoPainelLateral(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: IconButton(
                tooltip: estendido ? 'Recolher menu' : 'Expandir menu',
                onPressed: onAlternarEstendido,
                color: AppMenuModoEstilo.corIconeMenu(context),
                icon: Icon(
                  estendido ? Icons.menu_open_rounded : Icons.menu_rounded,
                  size: AppMenuModoEstilo.modoAtual(context) ==
                          AppMenuModoId.amplo
                      ? 28
                      : 24,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                itemCount: itens.length,
                itemBuilder: (context, index) {
                  final d = itens[index];
                  return _ItemMenuLateral(
                    destino: d,
                    selecionado: d == destinoAtual,
                    estendido: estendidoEfetivo,
                    badge: badgeDe(d),
                    onTap: () => onSelecionar(d),
                  );
                },
              ),
            ),
            if (quantidadeFavoritos > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$quantidadeFavoritos fav.',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: AppMenuModoEstilo.corRodapeLateral(context),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemMenuLateral extends StatelessWidget {
  const _ItemMenuLateral({
    required this.destino,
    required this.selecionado,
    required this.estendido,
    required this.badge,
    required this.onTap,
  });

  final MainMenuDestino destino;
  final bool selecionado;
  final bool estendido;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final padding = AppMenuModoEstilo.paddingItem(context, estendido);
    final icone = _iconeComBadge(
      context,
      destino: destino,
      selecionado: selecionado,
      badge: badge,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: AppMenuModoEstilo.decoracaoItemLateral(
              context,
              destino: destino,
              selecionado: selecionado,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: AppMenuModoEstilo.alturaItemMinima(context),
              ),
              child: Padding(
                padding: padding,
                child: estendido
                    ? Row(
                        children: [
                          icone,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              destino.titulo,
                              style: TextStyle(
                                fontSize:
                                    AppMenuModoEstilo.tamanhoFonteItem(context),
                                fontWeight: AppMenuModoEstilo.pesoTextoItem(
                                  context,
                                  selecionado,
                                ),
                                color: AppMenuModoEstilo.corTextoItem(
                                  context,
                                  destino: destino,
                                  selecionado: selecionado,
                                ),
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Center(child: icone),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _iconeComBadge(
  BuildContext context, {
  required MainMenuDestino destino,
  required bool selecionado,
  required int badge,
}) {
  final tamanho = AppMenuModoEstilo.tamanhoIconeItem(context);
  final icone = Icon(
    destino.icone,
    size: tamanho,
    color: AppMenuModoEstilo.corIconeItem(
      context,
      destino: destino,
      selecionado: selecionado,
    ),
  );
  if (badge <= 0) return icone;
  return Badge(
    label: Text(badge > 99 ? '99+' : '$badge'),
    child: icone,
  );
}

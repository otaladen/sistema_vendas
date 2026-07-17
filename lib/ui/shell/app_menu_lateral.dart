import 'package:flutter/material.dart';

import '../../domain/main_menu_destino.dart';
import '../../domain/main_menu_sub_destino.dart';
import '../../model/usuario_sistema.dart';
import '../theme/app_menu_modo_estilo.dart';
import '../theme/app_menu_modo_id.dart';
import '../theme/app_modulo_cores.dart';

/// Menu lateral esquerdo do shell desktop (classico ou personalizado).
class AppMenuLateral extends StatelessWidget {
  const AppMenuLateral({
    super.key,
    required this.itens,
    required this.destinoAtual,
    required this.subDestinoAtual,
    required this.usuarioLogado,
    required this.onSelecionar,
    required this.onSelecionarSub,
    required this.gruposExpandidos,
    required this.onAlternarGrupo,
    required this.estendido,
    required this.onAlternarEstendido,
    required this.badgeDe,
    this.badgeSubDe,
    this.quantidadeFavoritos = 0,
    this.larguraTela = 1200,
  });

  final List<MainMenuDestino> itens;
  final MainMenuDestino destinoAtual;
  final MainMenuSubDestino? subDestinoAtual;
  final UsuarioSistema usuarioLogado;
  final ValueChanged<MainMenuDestino> onSelecionar;
  final void Function(MainMenuDestino pai, MainMenuSubDestino sub) onSelecionarSub;
  final Set<MainMenuDestino> gruposExpandidos;
  final ValueChanged<MainMenuDestino> onAlternarGrupo;
  final bool estendido;
  final VoidCallback onAlternarEstendido;
  final int Function(MainMenuDestino destino) badgeDe;
  final int Function(MainMenuSubDestino sub)? badgeSubDe;
  final int quantidadeFavoritos;
  final double larguraTela;

  @override
  Widget build(BuildContext context) {
    final classico = AppMenuModoEstilo.usaRailPadrao(context);
    final estendidoEfetivo = estendido && larguraTela >= 1200;
    final largura = classico
        ? (estendidoEfetivo ? 200.0 : 72.0)
        : AppMenuModoEstilo.larguraLateralDe(context, estendidoEfetivo);

    return SizedBox(
      width: largura,
      child: DecoratedBox(
        decoration: classico
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              )
            : AppMenuModoEstilo.decoracaoPainelLateral(context),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: IconButton(
                tooltip: estendido ? 'Recolher menu' : 'Expandir menu',
                onPressed: onAlternarEstendido,
                color: classico
                    ? null
                    : AppMenuModoEstilo.corIconeMenu(context),
                icon: Icon(
                  estendido ? Icons.menu_open_rounded : Icons.menu_rounded,
                  size: classico
                      ? 24
                      : (AppMenuModoEstilo.modoAtual(context) ==
                              AppMenuModoId.amplo
                          ? 28
                          : 24),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                itemCount: itens.length,
                itemBuilder: (context, index) {
                  final d = itens[index];
                  if (MainMenuSubDestinoHelper.moduloTemSubmenu(d)) {
                    return _ItemMenuGrupo(
                      destino: d,
                      destinoAtual: destinoAtual,
                      subDestinoAtual: subDestinoAtual,
                      usuarioLogado: usuarioLogado,
                      expandido: gruposExpandidos.contains(d),
                      menuExpandido: estendidoEfetivo,
                      badge: badgeDe(d),
                      badgeSubDe: badgeSubDe,
                      onAlternarGrupo: () => onAlternarGrupo(d),
                      onSelecionarSub: (sub) => onSelecionarSub(d, sub),
                    );
                  }
                  return _ItemMenuLateral(
                    destino: d,
                    selecionado: d == destinoAtual && subDestinoAtual == null,
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: classico
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55)
                            : AppMenuModoEstilo.corRodapeLateral(context),
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

class _ItemMenuGrupo extends StatelessWidget {
  const _ItemMenuGrupo({
    required this.destino,
    required this.destinoAtual,
    required this.subDestinoAtual,
    required this.usuarioLogado,
    required this.expandido,
    required this.menuExpandido,
    required this.badge,
    this.badgeSubDe,
    required this.onAlternarGrupo,
    required this.onSelecionarSub,
  });

  final MainMenuDestino destino;
  final MainMenuDestino destinoAtual;
  final MainMenuSubDestino? subDestinoAtual;
  final UsuarioSistema usuarioLogado;
  final bool expandido;
  final bool menuExpandido;
  final int badge;
  final int Function(MainMenuSubDestino sub)? badgeSubDe;
  final VoidCallback onAlternarGrupo;
  final ValueChanged<MainMenuSubDestino> onSelecionarSub;

  bool get _grupoAtivo => destinoAtual == destino;

  List<MainMenuSubDestino> get _subitens =>
      MainMenuSubDestinoHelper.subitensDe(destino, usuarioLogado);

  Future<void> _abrirFlyoutRecolhido(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final selecionado = await showMenu<MainMenuSubDestino>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx + box.size.width + 4,
        pos.dy,
        pos.dx + box.size.width + 280,
        pos.dy + box.size.height,
      ),
      items: [
        for (final sub in _subitens)
          PopupMenuItem(
            value: sub,
            child: Row(
              children: [
                Icon(sub.icone, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(sub.titulo)),
              ],
            ),
          ),
      ],
    );
    if (selecionado != null) onSelecionarSub(selecionado);
  }

  @override
  Widget build(BuildContext context) {
    final padding = AppMenuModoEstilo.paddingItem(context, menuExpandido);
    final icone = _iconeComBadge(
      context,
      destino: destino,
      selecionado: _grupoAtivo,
      badge: badge,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: menuExpandido
                  ? onAlternarGrupo
                  : () => _abrirFlyoutRecolhido(context),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: AppMenuModoEstilo.decoracaoItemLateral(
                  context,
                  destino: destino,
                  selecionado: _grupoAtivo,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: AppMenuModoEstilo.alturaItemMinima(context),
                  ),
                  child: Padding(
                    padding: padding,
                    child: menuExpandido
                        ? Row(
                            children: [
                              icone,
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  destino.titulo,
                                  style: TextStyle(
                                    fontSize: AppMenuModoEstilo.tamanhoFonteItem(
                                      context,
                                    ),
                                    fontWeight:
                                        AppMenuModoEstilo.pesoTextoGrupoMenu(
                                      context,
                                      _grupoAtivo,
                                    ),
                                    letterSpacing: 0.1,
                                    color: AppMenuModoEstilo.corTextoItem(
                                      context,
                                      destino: destino,
                                      selecionado: _grupoAtivo,
                                    ),
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                expandido
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: AppMenuModoEstilo.corIconeItem(
                                  context,
                                  destino: destino,
                                  selecionado: _grupoAtivo,
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
          if (menuExpandido && expandido)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.65),
                      width: 1,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Column(
                    children: [
                      for (final sub in _subitens)
                        _ItemMenuSub(
                          sub: sub,
                          selecionado: subDestinoAtual == sub,
                          pai: destino,
                          badge: badgeSubDe?.call(sub) ?? 0,
                          onTap: () => onSelecionarSub(sub),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemMenuSub extends StatelessWidget {
  const _ItemMenuSub({
    required this.sub,
    required this.selecionado,
    required this.pai,
    required this.badge,
    required this.onTap,
  });

  final MainMenuSubDestino sub;
  final bool selecionado;
  final MainMenuDestino pai;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final corModulo = _corSub(context, sub);
    final fundo = selecionado
        ? corModulo.withValues(alpha: 0.18)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: fundo,
              borderRadius: BorderRadius.circular(12),
              border: selecionado
                  ? Border.all(color: corModulo.withValues(alpha: 0.45))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  if (badge > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Badge(
                        label: Text(badge > 99 ? '99+' : '$badge'),
                        child: Icon(
                          sub.icone,
                          size: 16,
                          color: selecionado ? corModulo : scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    Icon(
                      sub.icone,
                      size: 16,
                      color: selecionado ? corModulo : scheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sub.titulo,
                      style: TextStyle(
                        fontSize: AppMenuModoEstilo.tamanhoFonteSubItem(context),
                        fontWeight: AppMenuModoEstilo.pesoTextoSubMenu(
                          context,
                          selecionado,
                        ),
                        color: selecionado
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.withValues(alpha: 0.92),
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
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

Color _corSub(BuildContext context, MainMenuSubDestino sub) {
  final id = switch (sub) {
    MainMenuSubDestino.vendasOrcamentos => AppModuloId.orcamentos,
    MainMenuSubDestino.vendasListagem => AppModuloId.listagemVendas,
    MainMenuSubDestino.vendasRelatorios => AppModuloId.relatoriosVendas,
    MainMenuSubDestino.cadastrosProdutos => AppModuloId.produtos,
    MainMenuSubDestino.cadastrosKitsOrcamento => AppModuloId.kitsOrcamento,
    MainMenuSubDestino.cadastrosPromocoes => AppModuloId.promocoes,
    MainMenuSubDestino.cadastrosMotoristas => AppModuloId.motoristasCadastro,
    MainMenuSubDestino.cadastrosFuncionarios =>
      AppModuloId.funcionariosCadastro,
    MainMenuSubDestino.cadastrosClientes => AppModuloId.clientesCadastro,
    MainMenuSubDestino.cadastrosVendedores => AppModuloId.vendedoresCadastro,
    MainMenuSubDestino.cadastrosUsuarios => AppModuloId.usuariosCadastro,
    MainMenuSubDestino.fiscalImportarNfe ||
    MainMenuSubDestino.fiscalNotasImportadas ||
    MainMenuSubDestino.fiscalDevolucaoFornecedor ||
    MainMenuSubDestino.fiscalPendencias ||
    MainMenuSubDestino.fiscalNfeSaida ||
    MainMenuSubDestino.fiscalRelatorioMensal ||
    MainMenuSubDestino.fiscalExportarFechamento =>
      null,
    MainMenuSubDestino.financeiroTesouraria => AppModuloId.tesouraria,
    MainMenuSubDestino.financeiroContasReceber => AppModuloId.contasReceber,
    MainMenuSubDestino.financeiroContasPagar => AppModuloId.contasPagar,
    MainMenuSubDestino.financeiroRelatorioContasPagar =>
      AppModuloId.relatorioContasPagar,
    MainMenuSubDestino.financeiroRelatorioFiados => AppModuloId.relatorioFiados,
  };
  if (id == null) {
    return MainMenuDestino.notasFiscais.cor(context);
  }
  return AppModuloCores.modulo(context, id);
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

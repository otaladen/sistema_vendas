import 'package:flutter/material.dart';

import '../../domain/main_menu_sub_destino.dart';
import 'app_shell_scope.dart';
import 'main_menu_deps.dart';
import 'main_menu_sub_router.dart';

/// Abre sub-rotas de hub via shell (desktop) ou push (mobile).
class HubNavigation {
  HubNavigation._();

  static void abrirSub(BuildContext context, MainMenuSubDestino sub) {
    final deps = MainMenuDeps.maybeOf(context);
    if (deps == null || !sub.podeAcessar(deps.usuarioLogado)) return;

    final shell = AppShellScope.maybeOf(context);
    if (shell != null) {
      shell.irParaSub(sub.pai, sub);
      return;
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => MainMenuDeps(
          objectBox: deps.objectBox,
          produtoRepository: deps.produtoRepository,
          clienteRepository: deps.clienteRepository,
          vendaRepository: deps.vendaRepository,
          vendedorRepository: deps.vendedorRepository,
          funcionarioRepository: deps.funcionarioRepository,
          motoristaRepository: deps.motoristaRepository,
          usuarioLogado: deps.usuarioLogado,
          onLogout: deps.onLogout,
          lanSyncScheduler: deps.lanSyncScheduler,
          appConfigRepository: deps.appConfigRepository,
          printService: deps.printService,
          child: MainMenuSubRouter.pagina(
            sub,
            deps,
            navigatorContext: ctx,
          ),
        ),
      ),
    );
  }
}

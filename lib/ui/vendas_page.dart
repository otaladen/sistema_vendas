import 'package:flutter/material.dart';

import '../services/configuracoes_service.dart';
import '../domain/main_menu_sub_destino.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'layout/app_layout.dart';
import 'shell/hub_navigation.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';

class VendasPage extends StatelessWidget {
  const VendasPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.motoristaRepository,
    required this.configuracoesService,
    required this.printService,
    required this.usuarioLogado,
    required this.onLogout,
  });

  final dynamic produtoRepository;
  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final dynamic motoristaRepository;
  final ConfiguracoesService configuracoesService;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final u = usuarioLogado;
    final podeRelatorios =
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarRelatorios);
    final podeListagem = UsuarioPermissaoHelper.tem(
      u,
      PermissaoUsuario.acessarListagemVendas,
    );
    final podePdv = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv);
    final podeCaixa = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
    final podeOrcamentos = podePdv || podeCaixa || podeListagem;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestao de vendas'),
        actions: [
          ContaSessaoAppBarActions(
            login: u.login,
            onLogout: onLogout,
          ),
        ],
      ),
      body: AdaptiveHubBody(
        children: [
          HubNavButton(
            icon: Icons.request_quote_outlined,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.orcamentos),
            titulo: 'Orcamentos',
            habilitado: podeOrcamentos,
            onTap: () {
              if (!podeOrcamentos) return;
              HubNavigation.abrirSub(
                context,
                MainMenuSubDestino.vendasOrcamentos,
              );
            },
          ),
          HubNavButton(
            icon: Icons.view_list_outlined,
            corDestaque:
                AppModuloCores.modulo(context, AppModuloId.listagemVendas),
            titulo: 'Listagem de Vendas',
            habilitado: podeListagem,
            onTap: () {
              if (!podeListagem) return;
              HubNavigation.abrirSub(
                context,
                MainMenuSubDestino.vendasListagem,
              );
            },
          ),
          HubNavButton(
            icon: Icons.assessment_outlined,
            corDestaque:
                AppModuloCores.modulo(context, AppModuloId.relatoriosVendas),
            titulo: 'Relatorios',
            habilitado: podeRelatorios,
            onTap: () {
              if (!podeRelatorios) return;
              HubNavigation.abrirSub(
                context,
                MainMenuSubDestino.vendasRelatorios,
              );
            },
          ),
        ],
      ),
    );
  }
}

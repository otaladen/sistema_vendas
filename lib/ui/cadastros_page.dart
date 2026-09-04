import 'package:flutter/material.dart';

import '../domain/main_menu_sub_destino.dart';
import '../domain/modo_terminal_leve.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'layout/app_layout.dart';
import 'shell/hub_navigation.dart';
import 'theme/app_modulo_cores.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';

class CadastrosPage extends StatelessWidget {
  const CadastrosPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.printService,
    required this.onLogout,
    this.terminalLeve = false,
  });

  final dynamic produtoRepository;
  final dynamic clienteRepository;
  final dynamic vendaRepository;
  final dynamic vendedorRepository;
  final dynamic funcionarioRepository;
  final dynamic motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final PrintService printService;
  final VoidCallback onLogout;
  final bool terminalLeve;

  bool get _podeCadastros =>
      UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.cadastros);

  bool get _podeGerenciarUsuarios =>
      UsuarioPermissaoHelper.tem(
        usuarioLogado,
        PermissaoUsuario.gerenciarUsuarios,
      );

  void _abrir(BuildContext context, MainMenuSubDestino sub) {
    if (!sub.podeAcessar(usuarioLogado)) return;
    if (terminalLeve && !subDestinoPermitidoNoTerminalLeve(sub.name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastro disponivel apenas no PC servidor (terminal leve).',
          ),
        ),
      );
      return;
    }
    HubNavigation.abrirSub(context, sub);
  }

  bool _mostrar(MainMenuSubDestino sub) =>
      !terminalLeve || subDestinoPermitidoNoTerminalLeve(sub.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastros'),
        actions: [
          ContaSessaoAppBarActions(
            login: usuarioLogado.login,
            onLogout: onLogout,
          ),
        ],
      ),
      body: AdaptiveHubBody(
        children: [
          if (_mostrar(MainMenuSubDestino.cadastrosProdutos))
            HubNavButton(
              icon: Icons.inventory_2_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.produtos),
              titulo: 'Produtos',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosProdutos),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosListaPrecoExterna))
            HubNavButton(
              icon: Icons.price_change_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.listaPrecoExterna,
              ),
              titulo: 'Precos Itinga',
              habilitado: _podeCadastros,
              onTap: () => _abrir(
                context,
                MainMenuSubDestino.cadastrosListaPrecoExterna,
              ),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosKitsOrcamento))
            HubNavButton(
              icon: Icons.widgets_outlined,
              corDestaque:
                  AppModuloCores.modulo(context, AppModuloId.kitsOrcamento),
              titulo: 'Kits de orcamento',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosKitsOrcamento),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosPromocoes))
            HubNavButton(
              icon: Icons.local_offer_outlined,
              corDestaque:
                  AppModuloCores.modulo(context, AppModuloId.promocoes),
              titulo: 'Promocoes',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosPromocoes),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosMotoristas))
            HubNavButton(
              icon: Icons.local_shipping_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.motoristasCadastro,
              ),
              titulo: 'Motoristas',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosMotoristas),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosFuncionarios))
            HubNavButton(
              icon: Icons.badge_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.funcionariosCadastro,
              ),
              titulo: 'Funcionarios',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosFuncionarios),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosClientes))
            HubNavButton(
              icon: Icons.people_outline,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.clientesCadastro,
              ),
              titulo: 'Clientes',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosClientes),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosVendedores))
            HubNavButton(
              icon: Icons.storefront_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.vendedoresCadastro,
              ),
              titulo: 'Vendedores',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosVendedores),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosFornecedores))
            HubNavButton(
              icon: Icons.factory_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.fornecedoresCadastro,
              ),
              titulo: 'Fornecedores',
              habilitado: _podeCadastros,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosFornecedores),
            ),
          if (_mostrar(MainMenuSubDestino.cadastrosUsuarios))
            HubNavButton(
              icon: Icons.manage_accounts_outlined,
              corDestaque: AppModuloCores.modulo(
                context,
                AppModuloId.usuariosCadastro,
              ),
              titulo: 'Usuarios',
              habilitado: _podeGerenciarUsuarios,
              onTap: () =>
                  _abrir(context, MainMenuSubDestino.cadastrosUsuarios),
            ),
        ],
      ),
    );
  }
}

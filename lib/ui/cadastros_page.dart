import 'package:flutter/material.dart';

import '../domain/main_menu_sub_destino.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
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
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final PrintService printService;
  final VoidCallback onLogout;

  bool get _podeCadastros =>
      UsuarioPermissaoHelper.tem(usuarioLogado, PermissaoUsuario.cadastros);

  bool get _podeGerenciarUsuarios =>
      UsuarioPermissaoHelper.tem(
        usuarioLogado,
        PermissaoUsuario.gerenciarUsuarios,
      );

  void _abrir(BuildContext context, MainMenuSubDestino sub) {
    if (!sub.podeAcessar(usuarioLogado)) return;
    HubNavigation.abrirSub(context, sub);
  }

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
          HubNavButton(
            icon: Icons.inventory_2_outlined,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.produtos),
            titulo: 'Produtos',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosProdutos),
          ),
          HubNavButton(
            icon: Icons.widgets_outlined,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.kitsOrcamento),
            titulo: 'Kits de orcamento',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosKitsOrcamento),
          ),
          HubNavButton(
            icon: Icons.local_offer_outlined,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.promocoes),
            titulo: 'Promocoes',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosPromocoes),
          ),
          HubNavButton(
            icon: Icons.local_shipping_outlined,
            corDestaque:
                AppModuloCores.modulo(context, AppModuloId.motoristasCadastro),
            titulo: 'Motoristas',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosMotoristas),
          ),
          HubNavButton(
            icon: Icons.badge_outlined,
            corDestaque:
                AppModuloCores.modulo(context, AppModuloId.funcionariosCadastro),
            titulo: 'Funcionarios',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosFuncionarios),
          ),
          HubNavButton(
            icon: Icons.people_outline,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.clientesCadastro),
            titulo: 'Clientes',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosClientes),
          ),
          HubNavButton(
            icon: Icons.storefront_outlined,
            corDestaque:
                AppModuloCores.modulo(context, AppModuloId.vendedoresCadastro),
            titulo: 'Vendedores',
            habilitado: _podeCadastros,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosVendedores),
          ),
          HubNavButton(
            icon: Icons.manage_accounts_outlined,
            corDestaque: AppModuloCores.modulo(context, AppModuloId.usuariosCadastro),
            titulo: 'Usuarios',
            habilitado: _podeGerenciarUsuarios,
            onTap: () => _abrir(context, MainMenuSubDestino.cadastrosUsuarios),
          ),
        ],
      ),
    );
  }
}

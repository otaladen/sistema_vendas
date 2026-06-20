import 'package:flutter/material.dart';

import '../data/kit_orcamento_repository.dart';
import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'funcionarios_page.dart';
import 'kits_orcamento_page.dart';
import 'promocoes_page.dart';
import '../data/promocao_repository.dart';
import 'motoristas_page.dart';
import 'produtos_page.dart';
import 'usuarios_page.dart';
import 'vendedores_page.dart';
import 'layout/app_layout.dart';
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
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProdutosPage(
                      produtoRepository: produtoRepository,
                      printService: printService,
                      usuarioLogado: usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.widgets_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.kitsOrcamento),
              titulo: 'Kits de orcamento',
              habilitado: _podeCadastros,
              onTap: () {
                final kitRepo =
                    KitOrcamentoRepository(produtoRepository.objectBox);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KitsOrcamentoPage(
                      kitOrcamentoRepository: kitRepo,
                      produtoRepository: produtoRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.local_offer_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.promocoes),
              titulo: 'Promocoes',
              habilitado: _podeCadastros,
              onTap: () {
                final promoRepo =
                    PromocaoRepository(produtoRepository.objectBox);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PromocoesPage(
                      promocaoRepository: promoRepo,
                      produtoRepository: produtoRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.local_shipping_outlined,
              corDestaque:
                  AppModuloCores.modulo(context, AppModuloId.motoristasCadastro),
              titulo: 'Motoristas',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MotoristasPage(
                      motoristaRepository: motoristaRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.badge_outlined,
              corDestaque:
                  AppModuloCores.modulo(context, AppModuloId.funcionariosCadastro),
              titulo: 'Funcionarios',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FuncionariosPage(
                      funcionarioRepository: funcionarioRepository,
                      vendedorRepository: vendedorRepository,
                      vendaRepository: vendaRepository,
                      motoristaRepository: motoristaRepository,
                      usuarioRepository: UsuarioRepository(),
                      usuarioLogado: usuarioLogado,
                      onLogout: onLogout,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.people_outline,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.clientesCadastro),
              titulo: 'Clientes',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClientesPage(
                      clienteRepository: clienteRepository,
                      vendaRepository: vendaRepository,
                      vendedorRepository: vendedorRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.storefront_outlined,
              corDestaque:
                  AppModuloCores.modulo(context, AppModuloId.vendedoresCadastro),
              titulo: 'Vendedores',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendedoresPage(
                      vendedorRepository: vendedorRepository,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.manage_accounts_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.usuariosCadastro),
              titulo: 'Usuarios',
              habilitado: _podeGerenciarUsuarios,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsuariosPage(
                      usuarioRepository: UsuarioRepository(),
                      motoristaRepository: motoristaRepository,
                      usuarioLogado: usuarioLogado,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

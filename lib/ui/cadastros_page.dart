import 'package:flutter/material.dart';

import '../data/kit_orcamento_repository.dart';
import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'clientes_page.dart';
import 'funcionarios_page.dart';
import 'kits_orcamento_page.dart';
import 'motoristas_page.dart';
import 'produtos_page.dart';
import 'usuarios_page.dart';
import 'vendedores_page.dart';
import 'widgets/hub_nav_button.dart';

const Color _corProdutos = Color(0xFFE65100);
const Color _corMotoristas = Color(0xFF0277BD);
const Color _corFuncionarios = Color(0xFF455A64);
const Color _corClientes = Color(0xFF1565C0);
const Color _corVendedores = Color(0xFF2E7D32);
const Color _corUsuarios = Color(0xFF6A1B9A);
const Color _corKitsOrcamento = Color(0xFF5D4037);

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
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final PrintService printService;

  bool get _podeCadastros =>
      usuarioLogado.admin || usuarioLogado.podeCadastros;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastros')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HubNavButton(
              icon: Icons.inventory_2_outlined,
              corDestaque: _corProdutos,
              titulo: 'Produtos',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProdutosPage(
                          produtoRepository: produtoRepository,
                          printService: printService,
                        ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.widgets_outlined,
              corDestaque: _corKitsOrcamento,
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
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.local_shipping_outlined,
              corDestaque: _corMotoristas,
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
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.badge_outlined,
              corDestaque: _corFuncionarios,
              titulo: 'Funcionarios',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FuncionariosPage(
                      funcionarioRepository: funcionarioRepository,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.people_outline,
              corDestaque: _corClientes,
              titulo: 'Clientes',
              habilitado: _podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClientesPage(
                      clienteRepository: clienteRepository,
                      vendaRepository: vendaRepository,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.storefront_outlined,
              corDestaque: _corVendedores,
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
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.manage_accounts_outlined,
              corDestaque: _corUsuarios,
              titulo: 'Usuarios',
              habilitado: usuarioLogado.admin,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsuariosPage(
                      usuarioRepository: UsuarioRepository(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

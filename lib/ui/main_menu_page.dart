import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
import 'cadastros_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'vendas_page.dart';
import 'widgets/hub_nav_button.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.onLogout,
    required this.lanSyncScheduler,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler lanSyncScheduler;

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.lanSyncScheduler.iniciar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MENU PRINCIPAL'),
        actions: [
          Center(child: Text(widget.usuarioLogado.login)),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sair',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HubNavButton(
              icon: Icons.app_registration_outlined,
              corDestaque: HubNavColors.menuCadastros,
              titulo: 'Cadastros',
              habilitado:
                  widget.usuarioLogado.admin || widget.usuarioLogado.podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CadastrosPage(
                      produtoRepository: widget.produtoRepository,
                      clienteRepository: widget.clienteRepository,
                      vendaRepository: widget.vendaRepository,
                      vendedorRepository: widget.vendedorRepository,
                      funcionarioRepository: widget.funcionarioRepository,
                      motoristaRepository: widget.motoristaRepository,
                      usuarioLogado: widget.usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.inventory_2_outlined,
              corDestaque: HubNavColors.menuEstoque,
              titulo: 'Estoque',
              habilitado:
                  widget.usuarioLogado.admin || widget.usuarioLogado.podeEstoque,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EstoquePage(produtoRepository: widget.produtoRepository),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.point_of_sale_outlined,
              corDestaque: HubNavColors.menuVendas,
              titulo: 'Vendas',
              habilitado:
                  widget.usuarioLogado.admin || widget.usuarioLogado.podeVendas,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendasPage(
                      produtoRepository: widget.produtoRepository,
                      clienteRepository: widget.clienteRepository,
                      vendaRepository: widget.vendaRepository,
                      vendedorRepository: widget.vendedorRepository,
                      usuarioAtual: widget.usuarioLogado.login,
                      podeLeituraParcialCaixa:
                          widget.usuarioLogado.admin ||
                          widget.usuarioLogado.podeLeituraParcialCaixa,
                      podeManutencaoAuditoriaCaixa:
                          widget.usuarioLogado.admin ||
                          widget.usuarioLogado.podeManutencaoAuditoriaCaixa,
                      podeCancelarVendas:
                          widget.usuarioLogado.admin ||
                          widget.usuarioLogado.podeFinanceiro ||
                          widget.usuarioLogado.podeManutencaoAuditoriaCaixa,
                      motoristaRepository: widget.motoristaRepository,
                      podeGerenciarEntregas:
                          widget.usuarioLogado.admin ||
                          widget.usuarioLogado.podeEntregas,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.settings_outlined,
              corDestaque: HubNavColors.menuConfig,
              titulo: 'Configurações',
              habilitado:
                  widget.usuarioLogado.admin ||
                  widget.usuarioLogado.podeConfiguracoes,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConfiguracoesPage(
                      vendaRepository: widget.vendaRepository,
                      lanSyncScheduler: widget.lanSyncScheduler,
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

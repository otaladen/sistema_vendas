import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/sync/lan_sync_scheduler.dart';
import '../data/objectbox.dart';
import '../data/produto_repository.dart';
import '../services/lan_sync_server_manager.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'cadastros_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'financeiro/contas_pagar_page.dart';
import 'notas_fiscais_page.dart';
import 'vendas_page.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({
    super.key,
    required this.objectBox,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
    required this.onLogout,
    required this.lanSyncScheduler,
    required this.appConfigRepository,
    required this.printService,
  });

  final ObjectBox objectBox;
  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;
  final LanSyncScheduler lanSyncScheduler;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final config = await widget.appConfigRepository.carregarEmpresaConfig();
      if (Platform.isWindows &&
          config.redeModoServidor &&
          config.redeSincronizacaoAtiva) {
        await LanSyncServerManager.iniciarServidor(
          porta: config.redePortaServidor,
        );
      }
      await widget.lanSyncScheduler.iniciar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MENU PRINCIPAL'),
        actions: [
          ContaSessaoAppBarActions(
            login: widget.usuarioLogado.login,
            onLogout: widget.onLogout,
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
                  widget.usuarioLogado.admin ||
                  widget.usuarioLogado.podeCadastros,
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
                      printService: widget.printService,
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
                  widget.usuarioLogado.admin ||
                  widget.usuarioLogado.podeEstoque,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EstoquePage(
                      produtoRepository: widget.produtoRepository,
                      usuarioLogado: widget.usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.receipt_long_outlined,
              corDestaque: HubNavColors.menuNotasFiscais,
              titulo: 'Notas Fiscais',
              habilitado:
                  widget.usuarioLogado.admin ||
                  widget.usuarioLogado.podeEstoque,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotasFiscaisPage(
                      produtoRepository: widget.produtoRepository,
                    ),
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
                      appConfigRepository: widget.appConfigRepository,
                      printService: widget.printService,
                      usuarioAtual: widget.usuarioLogado.login,
                      onLogout: widget.onLogout,
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
              icon: Icons.payments_outlined,
              corDestaque: HubNavColors.menuFinanceiro,
              titulo: 'Financeiro',
              habilitado:
                  widget.usuarioLogado.admin ||
                  widget.usuarioLogado.podeFinanceiro,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ContasPagarPage(
                      objectBox: widget.objectBox,
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
                      objectBox: widget.produtoRepository.objectBox,
                      lanSyncScheduler: widget.lanSyncScheduler,
                      appConfigRepository: widget.appConfigRepository,
                      printService: widget.printService,
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

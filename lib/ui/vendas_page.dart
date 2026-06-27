import 'package:flutter/material.dart';

import '../data/app_config_repository.dart';
import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../data/motorista_repository.dart';
import '../domain/permissao_usuario.dart';
import '../domain/usuario_permissao_helper.dart';
import '../model/usuario_sistema.dart';
import '../services/print_service.dart';
import 'caixa/caixa_page.dart';
import 'entregas_page.dart';
import 'listagem_vendas_page.dart';
import 'orcamentos_page.dart';
import 'relatorios_page.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';
import 'layout/app_layout.dart';
import 'theme/app_modulo_cores.dart';

class VendasPage extends StatelessWidget {
  const VendasPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.motoristaRepository,
    required this.appConfigRepository,
    required this.printService,
    required this.usuarioLogado,
    required this.onLogout,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final MotoristaRepository motoristaRepository;
  final AppConfigRepository appConfigRepository;
  final PrintService printService;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final u = usuarioLogado;
    final podeCancelar = UsuarioPermissaoHelper.podeCancelarVendas(u);
    final podeRelatorios =
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarRelatorios);
    final podeListagem = UsuarioPermissaoHelper.tem(
      u,
      PermissaoUsuario.acessarListagemVendas,
    );
    final podePdv = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv);
    final podeCaixa = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
    final podeGerenciarEntregas =
        UsuarioPermissaoHelper.podeGerenciarEntregas(u);
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrcamentosPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      produtoRepository: produtoRepository,
                      vendedorRepository: vendedorRepository,
                      appConfigRepository: appConfigRepository,
                      printService: printService,
                      usuarioLogado: u,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.view_list_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.listagemVendas),
              titulo: 'Listagem de Vendas',
              habilitado: podeListagem,
              onTap: () {
                if (!podeListagem) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ListagemVendasPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                      produtoRepository: produtoRepository,
                      appConfigRepository: appConfigRepository,
                      printService: printService,
                      usuarioAtual: u.login,
                      podeCancelarVendas: podeCancelar,
                      usuarioLogado: u,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.assessment_outlined,
              corDestaque: AppModuloCores.modulo(context, AppModuloId.relatoriosVendas),
              titulo: 'Relatorios',
              habilitado: podeRelatorios,
              onTap: () {
                if (!podeRelatorios) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RelatoriosPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                      produtoRepository: produtoRepository,
                      appConfigRepository: appConfigRepository,
                            usuarioLogado: u,
                            usuarioAdmin: u.admin,
                            usuarioLogin: u.login,
                      onAbrirModuloEntregas: podeGerenciarEntregas
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntregasPage(
                                    vendaRepository: vendaRepository,
                                    produtoRepository: produtoRepository,
                                    motoristaRepository: motoristaRepository,
                                    appConfigRepository: appConfigRepository,
                                    usuarioAtual: u.login,
                                    podeGerenciarStatusEntrega:
                                        podeGerenciarEntregas,
                                    podeRegistrarPodEntrega:
                                        UsuarioPermissaoHelper
                                            .podeRegistrarPodEntrega(u),
                                    podeRegistrarDevolucaoTrocaSemSenha:
                                        podeCancelar,
                                  ),
                                ),
                              );
                            }
                          : null,
                      onAbrirModuloCaixa: () {
                        if (!podeCaixa) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CaixaPage(
                              clienteRepository: clienteRepository,
                              produtoRepository: produtoRepository,
                              vendaRepository: vendaRepository,
                              vendedorRepository: vendedorRepository,
                              appConfigRepository: appConfigRepository,
                              printService: printService,
                              usuarioLogado: u,
                              usuarioAtual: u.login,
                              podeCancelarVendas: podeCancelar,
                              podeLeituraParcialCaixa: UsuarioPermissaoHelper.tem(
                                u,
                                PermissaoUsuario.leituraParcialCaixa,
                              ),
                              podeVisualizarAuditoriaCaixa:
                                  UsuarioPermissaoHelper.tem(
                                u,
                                PermissaoUsuario.visualizarAuditoriaCaixa,
                              ),
                              podeManutencaoAuditoriaCaixa:
                                  UsuarioPermissaoHelper.tem(
                                u,
                                PermissaoUsuario.manutencaoAuditoriaCaixa,
                              ),
                              onLogout: onLogout,
                            ),
                          ),
                        );
                      },
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

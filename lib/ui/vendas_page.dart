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
import 'caixa_page.dart';
import 'entregas_page.dart';
import 'listagem_vendas_page.dart';
import 'ponto_de_venda_page.dart';
import 'relatorios_page.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';
import 'layout/app_layout.dart';

const Color _corPontoDeVenda = Color(0xFF2E7D32);
const Color _corCaixa = Color(0xFF00897B);
const Color _corEntregas = Color(0xFF0277BD);
const Color _corListagem = Color(0xFF3949AB);
const Color _corRelatorios = Color(0xFFEF6C00);

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
    final podePdv = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv);
    final podeCaixa = UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa);
    final podeEntregas =
        UsuarioPermissaoHelper.podeVisualizarEntregas(u);
    final podeGerenciarEntregas =
        UsuarioPermissaoHelper.podeGerenciarEntregas(u);
    final podeCancelar = UsuarioPermissaoHelper.podeCancelarVendas(u);
    final podeRelatorios =
        UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarRelatorios);
    final podeListagem = UsuarioPermissaoHelper.tem(
      u,
      PermissaoUsuario.acessarListagemVendas,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas'),
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
              icon: Icons.point_of_sale_outlined,
              corDestaque: _corPontoDeVenda,
              titulo: 'Ponto de Venda',
              habilitado: podePdv,
              onTap: () {
                if (!podePdv) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PontoDeVendaPage(
                      produtoRepository: produtoRepository,
                      clienteRepository: clienteRepository,
                      vendaRepository: vendaRepository,
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
              icon: Icons.receipt_long_outlined,
              corDestaque: _corCaixa,
              titulo: 'Caixa',
              habilitado: podeCaixa,
              onTap: () {
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
                      usuarioAtual: u.login,
                      podeLeituraParcialCaixa: UsuarioPermissaoHelper.tem(
                        u,
                        PermissaoUsuario.leituraParcialCaixa,
                      ),
                      podeVisualizarAuditoriaCaixa: UsuarioPermissaoHelper.tem(
                        u,
                        PermissaoUsuario.visualizarAuditoriaCaixa,
                      ),
                      podeManutencaoAuditoriaCaixa: UsuarioPermissaoHelper.tem(
                        u,
                        PermissaoUsuario.manutencaoAuditoriaCaixa,
                      ),
                      onLogout: onLogout,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.local_shipping_outlined,
              corDestaque: _corEntregas,
              titulo: 'Entregas',
              habilitado: podeEntregas,
              onTap: () {
                if (!podeEntregas) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntregasPage(
                      vendaRepository: vendaRepository,
                      produtoRepository: produtoRepository,
                      motoristaRepository: motoristaRepository,
                      appConfigRepository: appConfigRepository,
                      usuarioAtual: u.login,
                      podeGerenciarStatusEntrega: podeGerenciarEntregas,
                      podeRegistrarPodEntrega:
                          UsuarioPermissaoHelper.podeRegistrarPodEntrega(u),
                      podeRegistrarDevolucaoTrocaSemSenha: podeCancelar,
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.view_list_outlined,
              corDestaque: _corListagem,
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
                    ),
                  ),
                );
              },
            ),
            HubNavButton(
              icon: Icons.assessment_outlined,
              corDestaque: _corRelatorios,
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
                              usuarioAtual: u.login,
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

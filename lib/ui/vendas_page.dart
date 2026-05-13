import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../data/motorista_repository.dart';
import 'caixa_page.dart';
import 'entregas_page.dart';
import 'listagem_vendas_page.dart';
import 'ponto_de_venda_page.dart';
import 'relatorios_page.dart';
import 'widgets/conta_sessao_app_bar_actions.dart';
import 'widgets/hub_nav_button.dart';

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
    required this.usuarioAtual,
    required this.onLogout,
    required this.podeLeituraParcialCaixa,
    required this.podeManutencaoAuditoriaCaixa,
    required this.podeCancelarVendas,
    required this.podeGerenciarEntregas,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final MotoristaRepository motoristaRepository;
  final String usuarioAtual;
  final VoidCallback onLogout;
  final bool podeLeituraParcialCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final bool podeCancelarVendas;
  final bool podeGerenciarEntregas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendas'),
        actions: [
          ContaSessaoAppBarActions(login: usuarioAtual, onLogout: onLogout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HubNavButton(
              icon: Icons.point_of_sale_outlined,
              corDestaque: _corPontoDeVenda,
              titulo: 'Ponto de Venda',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PontoDeVendaPage(
                      produtoRepository: produtoRepository,
                      clienteRepository: clienteRepository,
                      vendaRepository: vendaRepository,
                      vendedorRepository: vendedorRepository,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.receipt_long_outlined,
              corDestaque: _corCaixa,
              titulo: 'Caixa',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CaixaPage(
                      clienteRepository: clienteRepository,
                      produtoRepository: produtoRepository,
                      vendaRepository: vendaRepository,
                      vendedorRepository: vendedorRepository,
                      usuarioAtual: usuarioAtual,
                      podeLeituraParcialCaixa: podeLeituraParcialCaixa,
                      podeManutencaoAuditoriaCaixa:
                          podeManutencaoAuditoriaCaixa,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.local_shipping_outlined,
              corDestaque: _corEntregas,
              titulo: 'Entregas',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntregasPage(
                      vendaRepository: vendaRepository,
                      produtoRepository: produtoRepository,
                      motoristaRepository: motoristaRepository,
                      usuarioAtual: usuarioAtual,
                      podeGerenciarStatusEntrega: podeGerenciarEntregas,
                      podeRegistrarDevolucaoTrocaSemSenha: podeCancelarVendas,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.view_list_outlined,
              corDestaque: _corListagem,
              titulo: 'Listagem de Vendas',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ListagemVendasPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                      produtoRepository: produtoRepository,
                      usuarioAtual: usuarioAtual,
                      podeCancelarVendas: podeCancelarVendas,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            HubNavButton(
              icon: Icons.assessment_outlined,
              corDestaque: _corRelatorios,
              titulo: 'Relatorios',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RelatoriosPage(
                      vendaRepository: vendaRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                      produtoRepository: produtoRepository,
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

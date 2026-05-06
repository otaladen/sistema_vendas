import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../data/motorista_repository.dart';
import '../domain/venda_service.dart';
import 'caixa_page.dart';
import 'entregas_page.dart';
import 'listagem_vendas_page.dart';
import 'ponto_de_venda_page.dart';
import 'relatorios_page.dart';

class VendasPage extends StatelessWidget {
  const VendasPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.motoristaRepository,
    required this.usuarioAtual,
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
  final bool podeLeituraParcialCaixa;
  final bool podeManutencaoAuditoriaCaixa;
  final bool podeCancelarVendas;
  final bool podeGerenciarEntregas;

  void _mostrarTokenSenhaDoDia(BuildContext context) {
    final vendaService = VendaService(vendaRepository);
    final token = vendaService.gerarSenhaDoDia();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Token para retirada'),
          content: SelectableText(
            token,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
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
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Ponto de Venda'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
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
                        podeManutencaoAuditoriaCaixa: podeManutencaoAuditoriaCaixa,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Caixa'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EntregasPage(
                            vendaRepository: vendaRepository,
                            motoristaRepository: motoristaRepository,
                            usuarioAtual: usuarioAtual,
                            podeGerenciarStatusEntrega: podeGerenciarEntregas,
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Entregas'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ListagemVendasPage(
                        vendaRepository: vendaRepository,
                        clienteRepository: clienteRepository,
                        vendedorRepository: vendedorRepository,
                        usuarioAtual: usuarioAtual,
                        podeCancelarVendas: podeCancelarVendas,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.view_list_outlined),
                label: const Text('Listagem de Vendas'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: () {
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
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('Relatorios'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _mostrarTokenSenhaDoDia(context),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Ver token de retirada'),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No Ponto de Venda voce monta o atendimento; no Caixa a venda e finalizada com baixa de estoque. Entregas controla frete e status. Listagem de Vendas mostra vendas finalizadas, com filtros e pesquisa. Relatorios reune vendas por periodo, ranking de produtos e clientes, estoque minimo e orcamentos em aberto.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

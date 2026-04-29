import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../domain/venda_service.dart';
import 'caixa_page.dart';
import 'entregas_page.dart';
import 'listagem_vendas_page.dart';
import 'ponto_de_venda_page.dart';

class VendasPage extends StatelessWidget {
  const VendasPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;

  void _mostrarTokenSenhaDoDia(BuildContext context) {
    final vendaService = VendaService(vendaRepository);
    final token = vendaService.gerarSenhaDoDia();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Token para guardar nota'),
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
                          EntregasPage(vendaRepository: vendaRepository),
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
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.view_list_outlined),
                label: const Text('Listagem de Vendas'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _mostrarTokenSenhaDoDia(context),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Ver token para guardar nota'),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Ponto de Venda monta orcamentos para atendimento. Caixa importa o orcamento e finaliza a venda com baixa de estoque. Entregas controla o fluxo de frete e status de entrega. Listagem de Vendas mostra as notas ja finalizadas no Caixa, com filtros e pesquisa.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

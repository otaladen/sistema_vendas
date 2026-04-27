import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import 'caixa_page.dart';
import 'entregas_page.dart';
import 'ponto_de_venda_page.dart';

class VendasPage extends StatelessWidget {
  const VendasPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;

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
                      builder: (_) => EntregasPage(
                        vendaRepository: vendaRepository,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Entregas'),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Ponto de Venda monta orcamentos para atendimento. Caixa importa o orcamento e finaliza a venda com baixa de estoque. Entregas controla o fluxo de frete e status de entrega.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

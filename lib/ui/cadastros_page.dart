import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/vendedor_repository.dart';
import 'clientes_page.dart';
import 'produtos_page.dart';
import 'vendedores_page.dart';

class CadastrosPage extends StatelessWidget {
  const CadastrosPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendedorRepository,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendedorRepository vendedorRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastros')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProdutosPage(produtoRepository: produtoRepository),
                    ),
                  );
                },
                child: const Text('Produtos'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClientesPage(clienteRepository: clienteRepository),
                    ),
                  );
                },
                child: const Text('Clientes'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendedoresPage(
                        vendedorRepository: vendedorRepository,
                      ),
                    ),
                  );
                },
                child: const Text('Vendedores'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

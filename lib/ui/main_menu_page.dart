import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import 'cadastros_page.dart';
import 'configuracoes_page.dart';
import 'estoque_page.dart';
import 'vendas_page.dart';

class MainMenuPage extends StatelessWidget {
  const MainMenuPage({
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MENU PRINCIPAL')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuButton(
              titulo: 'Cadastros',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CadastrosPage(
                      produtoRepository: produtoRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _MenuButton(
              titulo: 'Estoque',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EstoquePage(produtoRepository: produtoRepository),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _MenuButton(
              titulo: 'Vendas',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendasPage(
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
            _MenuButton(
              titulo: 'CONFIGURACOES',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfiguracoesPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.titulo, required this.onTap});

  final String titulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ElevatedButton(
        onPressed: onTap,
        child: Text(titulo, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/produto_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
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
    required this.usuarioLogado,
    required this.onLogout,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final UsuarioSistema usuarioLogado;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MENU PRINCIPAL'),
        actions: [
          Center(child: Text(usuarioLogado.login)),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sair',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuButton(
              titulo: 'Cadastros',
              habilitado: usuarioLogado.admin || usuarioLogado.podeCadastros,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CadastrosPage(
                      produtoRepository: produtoRepository,
                      clienteRepository: clienteRepository,
                      vendedorRepository: vendedorRepository,
                      usuarioLogado: usuarioLogado,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _MenuButton(
              titulo: 'Estoque',
              habilitado: usuarioLogado.admin || usuarioLogado.podeEstoque,
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
              habilitado: usuarioLogado.admin || usuarioLogado.podeVendas,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendasPage(
                      produtoRepository: produtoRepository,
                      clienteRepository: clienteRepository,
                      vendaRepository: vendaRepository,
                      vendedorRepository: vendedorRepository,
                      usuarioAtual: usuarioLogado.login,
                      podeManutencaoAuditoriaCaixa:
                          usuarioLogado.admin ||
                          usuarioLogado.podeManutencaoAuditoriaCaixa,
                      podeCancelarVendas:
                          usuarioLogado.admin ||
                          usuarioLogado.podeFinanceiro ||
                          usuarioLogado.podeManutencaoAuditoriaCaixa,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _MenuButton(
              titulo: 'Configurações',
              habilitado:
                  usuarioLogado.admin || usuarioLogado.podeConfiguracoes,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ConfiguracoesPage(vendaRepository: vendaRepository),
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

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.titulo,
    required this.onTap,
    this.habilitado = true,
  });

  final String titulo;
  final VoidCallback onTap;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ElevatedButton(
        onPressed: habilitado ? onTap : null,
        child: Text(titulo, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

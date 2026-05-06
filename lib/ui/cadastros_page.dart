import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/funcionario_repository.dart';
import '../data/motorista_repository.dart';
import '../data/produto_repository.dart';
import '../data/usuario_repository.dart';
import '../data/venda_repository.dart';
import '../data/vendedor_repository.dart';
import '../model/usuario_sistema.dart';
import 'clientes_page.dart';
import 'funcionarios_page.dart';
import 'motoristas_page.dart';
import 'produtos_page.dart';
import 'usuarios_page.dart';
import 'vendedores_page.dart';

class CadastrosPage extends StatelessWidget {
  const CadastrosPage({
    super.key,
    required this.produtoRepository,
    required this.clienteRepository,
    required this.vendaRepository,
    required this.vendedorRepository,
    required this.funcionarioRepository,
    required this.motoristaRepository,
    required this.usuarioLogado,
  });

  final ProdutoRepository produtoRepository;
  final ClienteRepository clienteRepository;
  final VendaRepository vendaRepository;
  final VendedorRepository vendedorRepository;
  final FuncionarioRepository funcionarioRepository;
  final MotoristaRepository motoristaRepository;
  final UsuarioSistema usuarioLogado;

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
                onPressed:
                    (usuarioLogado.admin || usuarioLogado.podeCadastros)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProdutosPage(produtoRepository: produtoRepository),
                    ),
                  );
                    }
                    : null,
                child: const Text('Produtos'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (usuarioLogado.admin || usuarioLogado.podeCadastros)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MotoristasPage(
                        motoristaRepository: motoristaRepository,
                      ),
                    ),
                  );
                    }
                    : null,
                child: const Text('Motoristas'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (usuarioLogado.admin || usuarioLogado.podeCadastros)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FuncionariosPage(
                        funcionarioRepository: funcionarioRepository,
                      ),
                    ),
                  );
                    }
                    : null,
                child: const Text('Funcionarios'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (usuarioLogado.admin || usuarioLogado.podeCadastros)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClientesPage(
                            clienteRepository: clienteRepository,
                            vendaRepository: vendaRepository,
                          ),
                    ),
                  );
                    }
                    : null,
                child: const Text('Clientes'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (usuarioLogado.admin || usuarioLogado.podeCadastros)
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendedoresPage(
                        vendedorRepository: vendedorRepository,
                      ),
                    ),
                  );
                    }
                    : null,
                child: const Text('Vendedores'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: usuarioLogado.admin
                    ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UsuariosPage(
                        usuarioRepository: UsuarioRepository(),
                      ),
                    ),
                  );
                    }
                    : null,
                child: const Text('Usuarios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

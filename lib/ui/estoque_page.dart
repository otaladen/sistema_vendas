import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/produto_repository.dart';

class EstoquePage extends StatelessWidget {
  const EstoquePage({super.key, required this.produtoRepository});

  final ProdutoRepository produtoRepository;

  String _formatarMoedaBRL(double valor) {
    final formatador = NumberFormat('#,##0.00', 'pt_BR');
    return 'R\$ ${formatador.format(valor)}';
  }

  @override
  Widget build(BuildContext context) {
    final produtos = produtoRepository.listarTodos();
    return Scaffold(
      appBar: AppBar(title: const Text('Estoque')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: produtos.length,
        itemBuilder: (context, index) {
          final produto = produtos[index];
          final abaixoMinimo = produto.estoque <= produto.quantidadeMinima;
          return Card(
            child: ListTile(
              title: Text('${produto.nome} (${produto.unidade})'),
              subtitle: Text(
                'SKU: ${produto.codigoInterno} | Estoque: ${produto.estoque} | Minimo: ${produto.quantidadeMinima}\n'
                'Custo: ${_formatarMoedaBRL(produto.precoCusto)} | Custo medio: ${_formatarMoedaBRL(produto.custoMedio)} | Venda: ${_formatarMoedaBRL(produto.precoVenda)}',
              ),
              isThreeLine: true,
              trailing: abaixoMinimo
                  ? const Text(
                      'Abaixo',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    )
                  : const Text('OK'),
            ),
          );
        },
      ),
    );
  }
}

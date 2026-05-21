import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/cliente_repository.dart';
import '../../data/produto_repository.dart';
import '../../data/venda_repository.dart';
import '../../data/vendedor_repository.dart';
import '../clientes_page.dart';
import '../produto_detalhe_venda_page.dart';
import 'relatorio_helpers.dart';

final DateFormat _dh = DateFormat('dd/MM/yyyy HH:mm');
final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');

String _fmtMoeda(double v) => 'R\$ ${_moeda.format(v)}';

/// Dialogo com itens e totais de uma venda finalizada.
Future<void> mostrarDetalheVendaRelatorio(
  BuildContext context, {
  required VendaRepository vendaRepository,
  required int vendaId,
}) async {
  final v = vendaRepository.obterPorId(vendaId);
  if (v == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda nao encontrada.')),
      );
    }
    return;
  }
  v.cliente.target;
  v.vendedor.target;
  final nota = v.numeroOrcamento > 0 ? '${v.numeroOrcamento}' : '${v.id}';
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final cliente = v.cliente.target?.nomeRazao ?? 'Sem cliente';
      return AlertDialog(
        title: Text('Venda $nota'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Data: ${_dh.format(v.data.toLocal())}'),
                Text('Cliente: $cliente'),
                Text('Total: ${_fmtMoeda(v.total)}'),
                Text('Lucro: ${_fmtMoeda(v.lucroTotal)}'),
                Text(
                  'Pagamento: ${relatorioRotuloFormaPagamento(v.formaPagamento)}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Itens',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...v.itens.map(
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${i.quantidade}x ${i.nomeProduto} · '
                      '${_fmtMoeda(i.subtotal)}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      );
    },
  );
}

/// Abre cadastro de clientes no registro informado.
Future<void> abrirClienteRelatorio(
  BuildContext context, {
  required ClienteRepository clienteRepository,
  required VendaRepository vendaRepository,
  required int clienteId,
  VendedorRepository? vendedorRepository,
}) async {
  if (clienteId <= 0) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ClientesPage(
        clienteRepository: clienteRepository,
        vendaRepository: vendaRepository,
        vendedorRepository: vendedorRepository,
        clienteIdInicial: clienteId,
      ),
    ),
  );
}

/// Modal de detalhe do produto (mesmo do PDV).
Future<void> abrirProdutoRelatorio(
  BuildContext context, {
  required ProdutoRepository produtoRepository,
  required int produtoId,
}) async {
  if (produtoId <= 0) return;
  final p = produtoRepository.obterPorId(produtoId);
  if (p == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto nao encontrado.')),
      );
    }
    return;
  }
  await mostrarModalDetalheProdutoVenda(context, produto: p);
}

/// Resumo rapido do cliente antes de abrir cadastro.
Future<void> mostrarResumoClienteRelatorio(
  BuildContext context, {
  required ClienteRepository clienteRepository,
  required VendaRepository vendaRepository,
  required int clienteId,
  VendedorRepository? vendedorRepository,
}) async {
  final c = clienteRepository.obterPorId(clienteId);
  if (c == null) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(c.nomeRazao),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.codigoInterno.trim().isNotEmpty)
            Text('Codigo: ${c.codigoInterno}'),
          Text('Limite credito: ${_fmtMoeda(c.limiteCredito)}'),
          if (c.bloqueadoFiado)
            Text(
              'Fiado bloqueado: ${c.motivoBloqueio.trim().isEmpty ? 'sim' : c.motivoBloqueio}',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          if (c.segmento.trim().isNotEmpty) Text('Segmento: ${c.segmento}'),
          if (c.categoriaComercial.trim().isNotEmpty)
            Text('Categoria: ${c.categoriaComercial}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            abrirClienteRelatorio(
              context,
              clienteRepository: clienteRepository,
              vendaRepository: vendaRepository,
              clienteId: clienteId,
              vendedorRepository: vendedorRepository,
            );
          },
          child: const Text('Abrir cadastro'),
        ),
      ],
    ),
  );
}

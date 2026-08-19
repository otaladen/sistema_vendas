import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/api/venda_api_repository.dart';
import '../../model/cliente.dart';
import '../../model/produto.dart';
import '../../model/venda.dart';
import '../clientes_page.dart';
import '../produto_detalhe_venda_page.dart';
import 'relatorio_helpers.dart';

final DateFormat _dh = DateFormat('dd/MM/yyyy HH:mm');
final NumberFormat _moeda = NumberFormat('#,##0.00', 'pt_BR');

String _fmtMoeda(double v) => 'R\$ ${_moeda.format(v)}';

/// Dialogo com itens e totais de uma venda finalizada.
Future<void> mostrarDetalheVendaRelatorio(
  BuildContext context, {
  required dynamic vendaRepository,
  required int vendaId,
  dynamic clienteRepository,
}) async {
  Venda? v = vendaRepository.obterPorId(vendaId) as Venda?;
  if (v == null && vendaRepository is VendaApiRepository) {
    try {
      v = await vendaRepository.atualizarVendaFinalizadaNoCache(vendaId);
    } catch (_) {}
  }
  // Orcamentos no terminal: se so temos o id no cache de orcamentos.
  if (v == null) {
    try {
      v = vendaRepository.obterPorId(vendaId) as Venda?;
    } catch (_) {}
  }
  if (v == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda nao encontrada.')),
      );
    }
    return;
  }
  if (vendaRepository is VendaApiRepository) {
    final itens = relatorioItensDaVenda(vendaRepository, v);
    if (itens.isEmpty) {
      try {
        await vendaRepository.carregarItensRemoto(vendaId);
      } catch (_) {}
    }
  }
  final clienteNome = relatorioNomeCliente(
    v,
    clienteRepository: clienteRepository,
  );
  final venda = v;
  final nota = venda.numeroOrcamento > 0 ? '${venda.numeroOrcamento}' : '${venda.id}';
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Venda $nota'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Data: ${_dh.format(venda.data.toLocal())}'),
                Text('Cliente: $clienteNome'),
                Text('Total: ${_fmtMoeda(venda.total)}'),
                Text('Lucro: ${_fmtMoeda(venda.lucroTotal)}'),
                Text(
                  'Pagamento: ${relatorioRotuloFormaPagamento(venda.formaPagamento)}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Itens',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                ...relatorioItensDaVenda(vendaRepository, venda).map(
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${i.quantidadeExibicaoVenda} x ${i.nomeProduto} · '
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
  required dynamic clienteRepository,
  required dynamic vendaRepository,
  required int clienteId,
  dynamic vendedorRepository,
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
  required dynamic produtoRepository,
  required int produtoId,
}) async {
  if (produtoId <= 0) return;
  final p = produtoRepository.obterPorId(produtoId) as Produto?;
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
  required dynamic clienteRepository,
  required dynamic vendaRepository,
  required int clienteId,
  dynamic vendedorRepository,
}) async {
  final c = clienteRepository.obterPorId(clienteId) as Cliente?;
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

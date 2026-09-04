import 'package:flutter/material.dart';

import '../../data/api/venda_api_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/item_venda_produto_orfao.dart';
import '../../model/item_venda.dart';
import '../../model/produto.dart';
import '../produtos/produto_pesquisa_dialog.dart';
import '../widgets/lan_api_feedback.dart';

/// Revincula itens de venda orfaos a um produto do catalogo (ex.: cadastro excluido).
abstract final class RevincularProdutoItemVendaFlow {
  RevincularProdutoItemVendaFlow._();

  static Produto? Function(int id) _obterProdutoDe(dynamic produtoRepository) {
    return (int id) {
      if (id <= 0 || produtoRepository == null) return null;
      try {
        return produtoRepository.obterPorId(id) as Produto?;
      } catch (_) {
        return null;
      }
    };
  }

  static Future<List<ItemVenda>> _carregarItens({
    required int vendaId,
    required dynamic vendaRepository,
  }) async {
    if (vendaRepository is VendaApiRepository) {
      return vendaRepository.carregarItensRemoto(vendaId);
    }
    if (vendaRepository is VendaRepository) {
      return vendaRepository.listarItensDaVendaGarantidos(vendaId);
    }
    try {
      final raw = vendaRepository.listarItensPorVenda(vendaId);
      if (raw is List<ItemVenda>) return raw;
      if (raw is List) return raw.whereType<ItemVenda>().toList();
    } catch (_) {}
    return const [];
  }

  static List<ItemVenda> _ordenarOrfaos(
    List<ItemVenda> orfaos, {
    String? mensagemErro,
  }) {
    final nomeErro = mensagemErro == null
        ? null
        : ItemVendaProdutoOrfaoHelper.nomeItemDoErro(mensagemErro);
    if (nomeErro == null || nomeErro.isEmpty) return orfaos;
    final copia = List<ItemVenda>.from(orfaos);
    copia.sort((a, b) {
      final aMatch = a.nomeProduto.trim() == nomeErro ? 0 : 1;
      final bMatch = b.nomeProduto.trim() == nomeErro ? 0 : 1;
      return aMatch.compareTo(bMatch);
    });
    return copia;
  }

  /// Pergunta produto para cada item orfao e persiste os vinculos.
  /// Retorna `true` se todos os orfaos foram revinculados.
  static Future<bool> resolverOrfaosDaVenda(
    BuildContext context, {
    required int vendaId,
    required dynamic vendaRepository,
    required dynamic produtoRepository,
    String? mensagemErro,
  }) async {
    if (produtoRepository == null) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Catalogo de produtos indisponivel para revincular itens.',
          ),
        ),
      );
      return false;
    }

    final obterProduto = _obterProdutoDe(produtoRepository);
    final itens = await _carregarItens(
      vendaId: vendaId,
      vendaRepository: vendaRepository,
    );
    var orfaos = ItemVendaProdutoOrfaoHelper.filtrarOrfaos(
      itens,
      obterProduto: obterProduto,
    );
    if (orfaos.isEmpty) {
      if (vendaRepository is VendaRepository) {
        orfaos = vendaRepository.listarItensSemProdutoVinculado(vendaId);
      }
    }
    if (orfaos.isEmpty) return false;

    orfaos = _ordenarOrfaos(orfaos, mensagemErro: mensagemErro);
    final vinculos = <int, int>{};

    for (final item in orfaos) {
      if (!context.mounted) return false;
      final produto = await _pedirProdutoParaItem(
        context,
        item: item,
        produtoRepository: produtoRepository,
        restantes: orfaos.length - vinculos.length,
      );
      if (produto == null) return false;
      vinculos[item.id] = produto.id;
    }

    try {
      await _aplicarVinculos(
        vendaId: vendaId,
        vinculos: vinculos,
        vendaRepository: vendaRepository,
      );
    } catch (e) {
      if (!context.mounted) return false;
      if (vendaRepository is VendaApiRepository) {
        LanApiFeedback.snackErro(context, e, prefixo: 'Falha ao revincular');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao revincular: $e')),
        );
      }
      return false;
    }

    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          vinculos.length == 1
              ? 'Item revinculado ao produto "${orfaos.first.nomeProduto}".'
              : '${vinculos.length} itens revinculados ao catalogo.',
        ),
        backgroundColor: Colors.green.shade700,
      ),
    );
    return true;
  }

  static Future<Produto?> _pedirProdutoParaItem(
    BuildContext context, {
    required ItemVenda item,
    required dynamic produtoRepository,
    required int restantes,
  }) async {
    final escolher = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Produto sem cadastro'),
          content: Text(
            restantes > 1
                ? 'O item "${item.nomeProduto}" perdeu o vinculo com o cadastro '
                    '(produto excluido).\n\n'
                    'Escolha o produto correto no catalogo. '
                    'Faltam $restantes item(ns) nesta venda.'
                : 'O item "${item.nomeProduto}" perdeu o vinculo com o cadastro '
                    '(produto excluido).\n\n'
                    'Escolha o produto correto no catalogo para emitir a NFC-e.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Escolher produto'),
            ),
          ],
        );
      },
    );
    if (escolher != true || !context.mounted) return null;
    return showProdutoPesquisaDialog(
      context: context,
      produtoRepository: produtoRepository,
    );
  }

  static Future<void> _aplicarVinculos({
    required int vendaId,
    required Map<int, int> vinculos,
    required dynamic vendaRepository,
  }) async {
    if (vendaRepository is VendaApiRepository) {
      await vendaRepository.revincularItensAoProduto(
        vendaId: vendaId,
        itemIdParaProdutoId: vinculos,
      );
      return;
    }
    if (vendaRepository is VendaRepository) {
      vendaRepository.revincularItensAoProduto(
        vendaId: vendaId,
        itemIdParaProdutoId: vinculos,
      );
      return;
    }
    throw StateError('Repositorio de venda nao suportado.');
  }
}

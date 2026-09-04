import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/item_venda_produto_orfao.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  group('ItemVendaProdutoOrfaoHelper', () {
    test('detecta item orfao quando produto foi excluido', () {
      final item = ItemVenda(
        nomeProduto: 'Areia 1/2m3',
        quantidade: 1,
        precoUnitario: 10,
        precoCustoUnitario: 5,
      )..produto.targetId = 99;

      expect(
        ItemVendaProdutoOrfaoHelper.itemSemProdutoVinculado(
          item,
          obterProduto: (_) => null,
        ),
        isTrue,
      );
    });

    test('item com produto valido nao e orfao', () {
      final produto = Produto(
        id: 5,
        codigoInterno: 'A1',
        nome: 'Areia',
        quantidadeMinima: 0,
        precoCusto: 1,
        precoVenda: 2,
      );
      final item = ItemVenda(
        nomeProduto: 'Areia',
        quantidade: 1,
        precoUnitario: 10,
        precoCustoUnitario: 5,
      )..produto.target = produto;

      expect(
        ItemVendaProdutoOrfaoHelper.itemSemProdutoVinculado(
          item,
          obterProduto: (id) => id == 5 ? produto : null,
        ),
        isFalse,
      );
    });

    test('parseia mensagem de erro sem produto vinculado', () {
      const msg = 'Item "Areia 1/2m3" sem produto vinculado.';
      expect(
        ItemVendaProdutoOrfaoHelper.pareceErroSemProdutoVinculado(msg),
        isTrue,
      );
      expect(
        ItemVendaProdutoOrfaoHelper.nomeItemDoErro(msg),
        'Areia 1/2m3',
      );
    });
  });
}

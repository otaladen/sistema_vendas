import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_unidade_exibicao.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/ui/produtos/produto_pesquisa_dialog.dart';

void main() {
  test('rotulo da coluna Un. ignora unidade de compra distinta', () {
    final produto = Produto(
      codigoInterno: '100',
      nome: 'Item teste',
      unidade: 'UN',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 12,
      precoCusto: 1,
      precoVenda: 2,
      preco1: 2,
      quantidadeMinima: 0,
    );

    expect(rotuloUnidadeProdutoLista(produto), isNot('UN'));
    expect(rotuloUnidadeVendaColunaTabela(produto), 'UN');
  });

  testWidgets(
    'celula Un. na tabela de cadastro exibe UN sem compra nem reticencias',
    (tester) async {
      final produto = Produto(
        codigoInterno: '100',
        nome: 'Item teste',
        unidade: 'UN',
        unidadeCompra: 'CX',
        quantidadePorEmbalagem: 12,
        precoCusto: 1,
        precoVenda: 2,
        preco1: 2,
        quantidadeMinima: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: ProdutoCadastroTabelaCelulaUnidade(produto: produto),
            ),
          ),
        ),
      );

      final unFinder = find.text('UN');
      expect(unFinder, findsOneWidget);
      expect(find.textContaining('CX'), findsNothing);
      expect(find.textContaining('·'), findsNothing);

      final unText = tester.widget<Text>(unFinder);
      expect(unText.data, 'UN');
      expect(unText.overflow, isNot(TextOverflow.ellipsis));

      expect(tester.takeException(), isNull);
    },
  );
}

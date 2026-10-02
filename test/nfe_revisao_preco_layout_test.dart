import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/nfe_revisao_preco.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/ui/fiscal/revisao_precos_nfe_dialog.dart';

class _ProdutoRepoFake {
  Produto? obterPorId(int id) => null;

  void salvar(Produto p) {}

  void invalidarCacheBusca() {}
}

void main() {
  List<NfeRevisaoPrecoItem> itensRevisao({int quantidade = 4}) {
    return [
      for (var i = 0; i < quantidade; i++)
        NfeRevisaoPrecoCalculo.deProduto(
          produto: Produto(
            id: i + 1,
            codigoInterno: 'SKU-${i + 1}',
            nome:
                'Produto de teste $i com descricao longa para conferencia de layout',
            quantidadeMinima: 0,
            precoCusto: 10.0 + i,
            precoVenda: 20.0 + i,
          )..preco2 = 18.0 + i
            ..preco3 = 16.0 + i,
          custoNovo: 12.0 + i,
          margemMinimaPadrao: 20,
        ),
    ];
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<NfeRevisaoPrecoItem> itens,
    bool precosExtrasAtivos = true,
  }) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: RevisaoPrecosNfeDialog(
                  itens: itens,
                  produtoRepository: _ProdutoRepoFake(),
                  numeroNota: 12345,
                  emitente: 'Fornecedor Teste LTDA',
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (!precosExtrasAtivos) {
      final chip = find.widgetWithText(FilterChip, 'Preco 2 e 3 (Atacado / Obra)');
      expect(chip, findsOneWidget);
      final chipWidget = tester.widget<FilterChip>(chip);
      if (chipWidget.selected) {
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
    } else {
      final chip = find.widgetWithText(FilterChip, 'Preco 2 e 3 (Atacado / Obra)');
      final chipWidget = tester.widget<FilterChip>(chip);
      if (!chipWidget.selected) {
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
    }
  }

  testWidgets(
    'tabela com Preco 2 e 3 ativo nao estoura em 1024x768 e mantem rodape',
    (tester) async {
      await pumpDialog(tester, itens: itensRevisao());

      expect(tester.takeException(), isNull);
      expect(find.text('Manter precos atuais'), findsOneWidget);
      expect(find.textContaining('Aplicar novos precos'), findsOneWidget);
      expect(find.text('Preco 3 atual'), findsOneWidget);
    },
  );

  testWidgets(
    'coluna Codigo / Produto respeita largura minima visivel com Preco 2 e 3',
    (tester) async {
      await pumpDialog(tester, itens: itensRevisao(quantidade: 2));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is ConstrainedBox &&
              w.constraints.minWidth == 180 &&
              w.constraints.maxWidth == double.infinity,
        ),
        findsWidgets,
      );

      final colunaProduto = find.byWidgetPredicate(
        (w) =>
            w is ConstrainedBox &&
            w.constraints.minWidth == 180 &&
            w.child is SizedBox,
      );
      expect(colunaProduto, findsWidgets);

      final renderBox = tester.renderObject<RenderBox>(colunaProduto.first);
      expect(renderBox.size.width, greaterThanOrEqualTo(180));

      expect(find.text('SKU-1'), findsOneWidget);
      expect(find.textContaining('Produto de teste 0'), findsOneWidget);
    },
  );
}

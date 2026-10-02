import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/ui/widgets/pdv_consulta_linha_produto.dart';

void main() {
  testWidgets(
    'coluna Un. exibe UN completo para Broca ACO Rapido 3/32 2.5mm',
    (tester) async {
      final produto = Produto(
        codigoInterno: '008001',
        nome: 'Broca ACO Rapido 3/32 2.5mm',
        unidade: ' UN ',
        precoCusto: 1,
        precoVenda: 12.5,
        preco1: 12.5,
        quantidadeMinima: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: PdvConsultaLinhaProduto(
                produto: produto,
                termoBusca: '',
                precos: const PdvConsultaPrecosLinha(
                  preco1Formatado: r'R$ 12,50',
                  preco2Formatado: r'R$ 11,00',
                  preco3Formatado: r'R$ 10,00',
                ),
                precoListaAtivo: 'preco1',
                onAdicionar: () {},
              ),
            ),
          ),
        ),
      );

      final unFinder = find.descendant(
        of: find.byType(PdvConsultaLinhaProduto),
        matching: find.text('UN'),
      );
      expect(unFinder, findsOneWidget);

      final unText = tester.widget<Text>(unFinder);
      expect(unText.data, 'UN');
      expect(unText.overflow, isNot(TextOverflow.ellipsis));
    },
  );
}

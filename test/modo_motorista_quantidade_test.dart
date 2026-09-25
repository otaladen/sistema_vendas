import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/buscar_na_loja.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/motorista/buscar_na_loja_quantidade_dialog.dart';

void main() {
  const nome = 'Formigres Catavento CL';

  Produto formigres({bool permiteFracionada = true}) => Produto(
        codigoInterno: 'FORM-CAT',
        nome: nome,
        unidade: 'M2',
        quantidadeMinima: 0,
        precoCusto: 30,
        precoVenda: 49.9,
        permiteQuantidadeFracionada: permiteFracionada,
      );

  ItemVenda itemFormigres({
    Produto? produto,
    int escala = ItemVenda.escalaQuantidadeMilesimos,
  }) {
    final item = ItemVenda(
      id: 21,
      nomeProduto: nome,
      quantidade: 6300,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      precoUnitario: 49.9,
      precoCustoUnitario: 30,
      lojaOrigemMercadoria: 'outra_loja',
      escalaQuantidade: escala,
    );
    if (produto != null) item.produto.target = produto;
    return item;
  }

  Venda vendaCarreto(ItemVenda item) => Venda()
    ..status = 'finalizada'
    ..statusEntrega = 'saiu_entrega'
    ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
    ..itens.add(item);

  group('limite do dialogo', () {
    test('6300 em milesimos vira limite de 6,3 M² (nao 6300)', () {
      final item = itemFormigres(produto: formigres());
      final entrada =
          BuscarNaLoja.entradaQuantidadeModal(vendaCarreto(item), item)!;

      expect(entrada.totalArmazenado, 6300);
      expect(entrada.totalExibicao, closeTo(6.3, 1e-9));
      expect(entrada.textoTotal, '6,3');
      expect(entrada.textoTotalComUnidade, '6,3 M²');
      expect(entrada.unidade, 'M²');
      expect(entrada.aceitaDecimal, isTrue);
      expect(entrada.validar('6,31'), 'Máximo 6,3 M²');
      expect(entrada.armazenadoDe('6300'), isNull);
    });

    test('escala gravada vale mesmo sem produto resolvido no terminal', () {
      final item = itemFormigres();
      final entrada =
          BuscarNaLoja.entradaQuantidadeModal(vendaCarreto(item), item)!;

      expect(entrada.textoTotal, '6,3');
      expect(entrada.unidade, isEmpty);
      expect(entrada.armazenadoDe('3,15'), 3150);
    });

    test('item legado M2 sem cadastro fracionado tambem limita em 6,3', () {
      final item = itemFormigres(
        produto: formigres(permiteFracionada: false),
        escala: ItemVenda.escalaQuantidadeLegado,
      );
      final entrada =
          BuscarNaLoja.entradaQuantidadeModal(vendaCarreto(item), item)!;

      expect(entrada.textoTotalComUnidade, '6,3 M²');
    });
  });

  group('digitacao do motorista', () {
    late EntradaQuantidadeBuscarNaLoja entrada;

    setUp(() {
      final item = itemFormigres(produto: formigres());
      entrada = BuscarNaLoja.entradaQuantidadeModal(vendaCarreto(item), item)!;
    });

    test('decimal com virgula ou ponto e reconvertido para milesimos', () {
      expect(entrada.armazenadoDe('3,15'), 3150);
      expect(entrada.armazenadoDe('3.15'), 3150);
      expect(entrada.armazenadoDe(' 0,5 '), 500);
      expect(entrada.armazenadoDe('6,3'), 6300);
      expect(entrada.armazenadoDe('6,300'), 6300);
    });

    test('rejeita vazio, zero, negativo e texto invalido', () {
      expect(entrada.armazenadoDe(''), isNull);
      expect(entrada.armazenadoDe('0'), isNull);
      expect(entrada.armazenadoDe('0,0001'), isNull);
      expect(entrada.armazenadoDe('-1'), isNull);
      expect(entrada.armazenadoDe('abc'), isNull);
    });
  });

  group('dialogo', () {
    final campo = find.byKey(const ValueKey('buscar_na_loja_quantidade'));

    /// Abre o dialogo e devolve getter do valor retornado ao fechar.
    Future<int? Function()> abrir(
      WidgetTester tester, {
      int quantidadeBuscarNaLoja = 0,
    }) async {
      final item = itemFormigres(produto: formigres())
        ..quantidadeBuscarNaLoja = quantidadeBuscarNaLoja;
      final entrada =
          BuscarNaLoja.entradaQuantidadeModal(vendaCarreto(item), item)!;
      int? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  resultado = await mostrarBuscarNaLojaQuantidadeDialog(
                    context,
                    nomeProduto: item.nomeProduto,
                    entrada: entrada,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return () => resultado;
    }

    String textoCampo(WidgetTester tester) =>
        tester.widget<TextField>(campo).controller!.text;

    testWidgets('abre com limite 6,3 M², sem lista de opcoes', (tester) async {
      await abrir(tester);

      expect(find.text('Buscar na Loja - $nome'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.text('Buscar Todos (6,3 M²)'), findsOneWidget);
      expect(find.textContaining('6300'), findsNothing);
      expect(textoCampo(tester), '6,3');
      expect(tester.widget<TextField>(campo).decoration!.suffixText, 'M²');
    });

    testWidgets('digitar 3,15 devolve 3150 ao salvar', (tester) async {
      final resultado = await abrir(tester);

      await tester.enterText(campo, '3,15');
      await tester.pump();
      await tester.tap(find.text('Avisar pátio'));
      await tester.pumpAndSettle();

      expect(resultado(), 3150);
    });

    testWidgets('Buscar Todos preenche 6,3 e devolve 6300', (tester) async {
      final resultado = await abrir(tester, quantidadeBuscarNaLoja: 1000);
      expect(textoCampo(tester), '1');

      await tester.tap(find.text('Buscar Todos (6,3 M²)'));
      await tester.pump();
      expect(textoCampo(tester), '6,3');

      await tester.tap(find.text('Avisar pátio'));
      await tester.pumpAndSettle();
      expect(resultado(), 6300);
    });

    testWidgets('valor acima do limite desabilita Avisar pátio',
        (tester) async {
      await abrir(tester);

      await tester.enterText(campo, '7');
      await tester.pump();

      expect(find.text('Máximo 6,3 M²'), findsWidgets);
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Avisar pátio'),
      );
      expect(botao.onPressed, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/vendas/cancelar_venda_ui.dart';
import 'package:sistema_vendas/ui/vendas/listagem_venda_item_ui.dart';
import 'package:sistema_vendas/ui/vendas/listagem_vendas_tabela.dart';

Venda _vendaFinalizada({
  required int id,
  required int numeroControle,
  int numeroOrcamento = 0,
  String nfceNumero = '',
  String nfceChave = '',
}) {
  return Venda(
    id: id,
    status: 'finalizada',
    numeroControle: numeroControle,
    numeroOrcamento: numeroOrcamento,
    nfceNumero: nfceNumero,
    nfceChaveAcesso: nfceChave,
    total: 50,
    formaPagamento: 'dinheiro',
  );
}

ListagemVendaItemUi _itemUi(Venda v, {required String badgeNumero}) {
  return ListagemVendaItemUi(
    venda: v,
    titulo: '',
    status: 'Concluída',
    statusCor: const Color(0xFF000000),
    dataHora: '01/01/2026 10:00',
    cliente: 'Cliente teste',
    vendedor: 'Vendedor',
    pagamento: 'Dinheiro',
    entrega: 'Retirada',
    badgeNumero: badgeNumero,
    totalFormatado: 'R\$ 50,00',
    cancelada: false,
  );
}

void main() {
  group('rotuloVendaParaUsuario', () {
    test('usa numeroControle e nao id nem numeroOrcamento', () {
      final v = _vendaFinalizada(
        id: 99,
        numeroControle: 2527,
        numeroOrcamento: 148,
      );
      expect(rotuloVendaParaUsuario(v), 'Venda #2527');
    });

    test('sem controle exibe NFC-e quando emitida', () {
      final v = _vendaFinalizada(
        id: 0,
        numeroControle: 0,
        numeroOrcamento: 0,
        nfceNumero: '1892',
        nfceChave: '35260101234567890123456789012345678901234567',
      );
      expect(rotuloVendaParaUsuario(v), 'NFC-e 1892');
    });

    test('texto do modal de confirmacao reflete controle da linha', () {
      final v = _vendaFinalizada(
        id: 500,
        numeroControle: 2527,
        numeroOrcamento: 140,
      );
      expect(
        'Cancelar ${rotuloVendaParaUsuario(v)}?',
        'Cancelar Venda #2527?',
      );
    });
  });

  group('ListagemVendasTabela cancelar', () {
    testWidgets(
      'acao cancelar recebe a venda exibida na linha (controle 2527)',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final v2527 = _vendaFinalizada(
          id: 100,
          numeroControle: 2527,
          numeroOrcamento: 148,
        );
        final v2528 = _vendaFinalizada(
          id: 101,
          numeroControle: 2528,
          numeroOrcamento: 149,
        );

        Venda? vendaNoCancelamento;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListagemVendasTabela(
                itens: [
                  _itemUi(v2528, badgeNumero: '2528'),
                  _itemUi(v2527, badgeNumero: '2527'),
                ],
                onTapItem: (_) {},
                onAcaoMenu: (acao, item) {
                  if (acao == 'cancelar') vendaNoCancelamento = item.venda;
                },
                menuBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'cancelar',
                    child: Text('Cancelar venda'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2527'), findsOneWidget);

        final menus = find.byType(PopupMenuButton<String>);
        expect(menus, findsNWidgets(2));
        await tester.tap(menus.at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar venda'));
        await tester.pumpAndSettle();

        expect(vendaNoCancelamento, isNotNull);
        expect(vendaNoCancelamento!.numeroControle, 2527);
        expect(vendaNoCancelamento!.id, 100);
        expect(
          'Cancelar ${rotuloVendaParaUsuario(vendaNoCancelamento!)}?',
          'Cancelar Venda #2527?',
        );
      },
    );

    testWidgets(
      'ordenacao local da tabela nao desalinha venda ao cancelar',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final vA = _vendaFinalizada(id: 1, numeroControle: 100);
        final vB = _vendaFinalizada(id: 2, numeroControle: 200);

        Venda? capturada;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListagemVendasTabela(
                itens: [
                  _itemUi(vB, badgeNumero: '200'),
                  _itemUi(vA, badgeNumero: '100'),
                ],
                onTapItem: (_) {},
                onAcaoMenu: (acao, item) {
                  if (acao == 'cancelar') capturada = item.venda;
                },
                menuBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'cancelar',
                    child: Text('Cancelar venda'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('#').first);
        await tester.pumpAndSettle();

        expect(find.text('100'), findsOneWidget);
        final linha100 = find.ancestor(
          of: find.text('100'),
          matching: find.byType(InkWell),
        );
        expect(linha100, findsOneWidget);
        final menuLinha100 = find.descendant(
          of: linha100,
          matching: find.byType(PopupMenuButton<String>),
        );
        await tester.tap(menuLinha100);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar venda'));
        await tester.pumpAndSettle();

        expect(capturada?.numeroControle, 100);
      },
    );
  });
}

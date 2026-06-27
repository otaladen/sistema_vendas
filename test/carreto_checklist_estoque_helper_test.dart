import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entregas/carreto_checklist_estoque_helper.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/movimento_estoque.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('ehErroAoMarcarSaiu reconhece mensagem de reserva', () {
    expect(
      CarretoChecklistEstoqueHelper.ehErroAoMarcarSaiu(
        StateError(
          'Nao foi possivel marcar "Saiu": estoque insuficiente.\n'
          'Tinta: reservado 0, necessario 1 para o romaneio.',
        ),
      ),
      isTrue,
    );
  });

  test('problemasReservaCarretoPendente detecta reserva insuficiente', () {
    final venda = Venda(status: 'finalizada', carretoReservaAteSaida: true);
    final produto = Produto(
      codigoInterno: 't1',
      nome: 'Tinta Coral',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 100,
      estoqueReal: 5,
      estoqueReservado: 0,
    );
    final item = ItemVenda(
      nomeProduto: 'Tinta Coral',
      quantidade: 1,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 100,
      precoCustoUnitario: 50,
    );
    item.produto.target = produto;
    venda.itens.add(item);

    final problemas =
        CarretoChecklistEstoqueHelper.problemasReservaCarretoPendente(venda);
    expect(problemas.length, 1);
    expect(problemas.first, contains('reservado 0'));
  });

  test('resumirKardexPedido lista movimentos com referencia do pedido', () {
    final venda = Venda(status: 'finalizada', numeroOrcamento: 137);
    venda.carretoReservaAteSaida = true;
    final produto = Produto(
      codigoInterno: 't2',
      nome: 'Tinta',
      quantidadeMinima: 0,
      precoCusto: 1,
      precoVenda: 1,
      estoqueReal: 2,
      estoqueReservado: 0,
    );
    produto.id = 10;
    final item = ItemVenda(
      nomeProduto: 'Tinta',
      quantidade: 1,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
    );
    item.produto.target = produto;
    venda.itens.add(item);

    final mov = MovimentoEstoque(
      tipoMovimento: 'finalizacaoAjustaReserva',
      deltaReserva: 1,
      saldoReservaAntes: 0,
      saldoReservaDepois: 1,
      documentoReferencia: 'Controle 137',
    );

    final linhas = CarretoChecklistEstoqueHelper.resumirKardexPedido(
      venda: venda,
      listarMovimentos: (_) => [mov],
    );

    expect(linhas.any((l) => l.contains('reservado 0')), isTrue);
    expect(linhas.any((l) => l.contains('Reserva na finalizacao')), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('vendaDeveImprimirBlocoEntrega true para carreto', () {
    final venda = Venda(
      tipoEntrega: 'entrega_loja',
      enderecoEntrega: 'Rua X, 1',
    );
    expect(EntregaVendaHelper.vendaDeveImprimirBlocoEntrega(venda), isTrue);
  });

  test('vendaDeveImprimirBlocoEntrega false para leva agora', () {
    final venda = Venda(tipoEntrega: 'retirada');
    expect(EntregaVendaHelper.vendaDeveImprimirBlocoEntrega(venda), isFalse);
  });

  test('vendaDeveImprimirBlocoEntrega false para cotacao sem endereco', () {
    final venda = Venda(
      tipoEntrega: 'entrega_loja',
      statusEntrega: 'cotacao',
      valorFrete: 50,
    );
    expect(EntregaVendaHelper.vendaDeveImprimirBlocoEntrega(venda), isFalse);
    expect(
      EntregaVendaHelper.linhasBlocoEntregaImpressao(
        venda: venda,
        cliente: Cliente(nomeRazao: 'Cliente teste'),
      ),
      isEmpty,
    );
  });

  test('linhasBlocoEntregaImpressao monta nome telefone endereco e obs', () {
    final venda = Venda(
      tipoEntrega: 'entrega_loja',
      enderecoEntrega: 'Av. Brasil, 500 | Meier | Rio - RJ',
      observacaoEntrega: 'Descarregar na obra',
    );
    final cliente = Cliente(
      nomeRazao: 'Construtora ABC',
      telefone: '21999998888',
    );
    final linhas = EntregaVendaHelper.linhasBlocoEntregaImpressao(
      venda: venda,
      cliente: cliente,
    );
    expect(linhas.any((l) => l.contains('Construtora ABC')), isTrue);
    expect(linhas.any((l) => l.contains('999998888')), isTrue);
    expect(linhas.any((l) => l.contains('Av. Brasil')), isTrue);
    expect(linhas.any((l) => l.contains('Descarregar na obra')), isTrue);
  });

  test('linhasBlocoEntregaImpressao detecta carreto por item misto', () {
    final venda = Venda(tipoEntrega: 'misto');
    final itens = <ItemVenda>[
      ItemVenda(
        nomeProduto: 'A',
        quantidade: 1,
        precoUnitario: 1,
        precoCustoUnitario: 0.5,
        tipoEntregaItem: 'retirada',
      ),
      ItemVenda(
        nomeProduto: 'B',
        quantidade: 1,
        precoUnitario: 1,
        precoCustoUnitario: 0.5,
        tipoEntregaItem: 'entrega_loja',
      ),
    ];
    expect(
      EntregaVendaHelper.vendaDeveImprimirBlocoEntrega(venda, itens: itens),
      isTrue,
    );
  });
}

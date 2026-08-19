import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/entregas/buscar_na_loja.dart';
import 'package:sistema_vendas/domain/entregas/loja_origem_mercadoria.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/gerenciador_estoque_service.dart';

void main() {
  test('status solicitado e separado', () {
    expect(BuscarNaLoja.ehSolicitado('solicitado'), isTrue);
    expect(BuscarNaLoja.ehSeparado('separado'), isTrue);
    expect(BuscarNaLoja.ehSolicitado(''), isFalse);
  });

  test('nao pede item que ja e desta loja', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 1,
      nomeProduto: 'Tinta',
      quantidade: 2,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.local,
    );
    expect(BuscarNaLoja.podeSolicitarItem(venda, item), isFalse);
  });

  test('pede item de outra loja em rota', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 2,
      nomeProduto: 'Tinta',
      quantidade: 2,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
    );
    expect(BuscarNaLoja.podeSolicitarItem(venda, item), isTrue);
  });

  test('rotulo e origem misto quando so parte busca nesta loja', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 3,
      nomeProduto: 'Cimento Portland CP II Poty 50kg',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
      quantidadeBuscarNaLoja: 1,
    );
    expect(BuscarNaLoja.qtdCarga(venda, item), 3);
    expect(BuscarNaLoja.quantidadeEfetiva(venda, item), 1);
    expect(BuscarNaLoja.rotuloQuantidade(venda, item), '1 de 3');
    expect(
      BuscarNaLoja.origemAposConfirmar(venda, item),
      LojaOrigemMercadoria.misto,
    );
    expect(BuscarNaLoja.clampQuantidade(venda, item, 9), 3);
    expect(BuscarNaLoja.parseQuantidades({'3': 1})[3], 1);
  });

  test('origem local quando busca a linha inteira', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'roteirizada',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 4,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
      quantidadeBuscarNaLoja: 3,
    );
    expect(BuscarNaLoja.rotuloQuantidade(venda, item), '3x');
    expect(
      BuscarNaLoja.origemAposConfirmar(venda, item),
      LojaOrigemMercadoria.local,
    );
  });

  test('pode alterar quantidade enquanto ainda solicitado', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 5,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
      buscarNaLojaStatus: BuscarNaLoja.solicitado,
      quantidadeBuscarNaLoja: 3,
    );
    expect(BuscarNaLoja.podeSolicitarItem(venda, item), isTrue);
  });

  test('resumo pendentes mostra recorte 1 de 3', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 6,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      buscarNaLojaStatus: BuscarNaLoja.solicitado,
      quantidadeBuscarNaLoja: 1,
    );
    expect(
      BuscarNaLoja.resumoPendentes(venda, [item]),
      'Buscar nesta loja: 1 de 3 Cimento',
    );
  });

  test('fisico desta loja no carreto usa so o recorte', () {
    final venda = Venda(
      status: 'finalizada',
      tipoEntrega: 'entrega_loja',
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.misto,
      buscarNaLojaStatus: BuscarNaLoja.separado,
      quantidadeBuscarNaLoja: 1,
    );
    expect(
      GerenciadorEstoqueService.quantidadeItemParaEstoqueCarreto(item),
      3,
    );
    expect(
      GerenciadorEstoqueService.quantidadeFisicaDestaLojaCarreto(venda, item),
      1,
    );
  });

  test('pode cancelar pedido ainda so solicitado', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 7,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
      buscarNaLojaStatus: BuscarNaLoja.solicitado,
      quantidadeBuscarNaLoja: 1,
    );
    expect(BuscarNaLoja.podeCancelarItem(venda, item), isTrue);
    expect(BuscarNaLoja.podeSolicitarItem(venda, item), isTrue);
  });

  test('pode desistir depois do patio aceitar separar', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'saiu_entrega',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 8,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.misto,
      buscarNaLojaStatus: BuscarNaLoja.separado,
      quantidadeBuscarNaLoja: 1,
    );
    expect(BuscarNaLoja.podeCancelarItem(venda, item), isTrue);
    expect(BuscarNaLoja.podeSolicitarItem(venda, item), isFalse);
  });

  test('nao desiste depois de entregue', () {
    final venda = Venda(
      status: 'finalizada',
      statusEntrega: 'entregue',
      tipoEntrega: 'entrega_loja',
    );
    final item = ItemVenda(
      id: 9,
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.local,
      buscarNaLojaStatus: BuscarNaLoja.separado,
      quantidadeBuscarNaLoja: 3,
    );
    expect(BuscarNaLoja.podeCancelarItem(venda, item), isFalse);
  });

  test('solicitado sem confirmacao do patio nao baixa fisico', () {
    final venda = Venda(
      status: 'finalizada',
      tipoEntrega: 'entrega_loja',
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 3,
      tipoEntregaItem: 'entrega_loja',
      precoUnitario: 1,
      precoCustoUnitario: 1,
      lojaOrigemMercadoria: LojaOrigemMercadoria.outraLoja,
      buscarNaLojaStatus: BuscarNaLoja.solicitado,
      quantidadeBuscarNaLoja: 1,
    );
    expect(
      GerenciadorEstoqueService.quantidadeFisicaDestaLojaCarreto(venda, item),
      0,
    );
  });
}

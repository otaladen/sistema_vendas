import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_logistica_sugerida.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  ItemVenda itemKg(int q) {
    final p = Produto(
      codigoInterno: '1',
      nome: 'Cimento',
      unidade: 'KG',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 10,
    );
    return ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: q,
      precoUnitario: 10,
      precoCustoUnitario: 1,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    )..produto.target = p;
  }

  ItemVenda itemCarreto(int q) {
    final i = itemKg(q);
    i.tipoEntregaItem = EntregaVendaHelper.tipoEntregaLoja;
    return i;
  }

  test('somente retirada sugere modalidade 9', () {
    final v = Venda(
      tipoEntrega: EntregaVendaHelper.tipoRetirada,
    )..itens.add(itemKg(10));
    final s = NfeLogisticaSugerida.calcular(v);
    expect(s.modalidadeFrete, 9);
    expect(s.temTransporteLoja, isFalse);
  });

  test('carreto sugere CIF e peso dos itens de entrega', () {
    final v = Venda(
      tipoEntrega: EntregaVendaHelper.tipoMisto,
      valorFrete: 50,
    )
      ..itens.add(itemKg(5))
      ..itens.add(itemCarreto(100));
    final s = NfeLogisticaSugerida.calcular(v);
    expect(s.modalidadeFrete, 0);
    expect(s.temTransporteLoja, isTrue);
    expect(s.pesoBrutoKg, greaterThan(50));
  });

  test('frete sem carreto ainda usa CIF', () {
    final v = Venda(valorFrete: 30)..itens.add(itemKg(2));
    final s = NfeLogisticaSugerida.calcular(v);
    expect(s.modalidadeFrete, 0);
  });
}

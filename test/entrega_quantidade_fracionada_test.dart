import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/romaneio_carga_merge.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('Entregas exibe 18,9 e subtotal correto (nao 18900 / 642411)', () {
    final produto = Produto(
      codigoInterno: 'FORM',
      nome: 'Formigres Catavento CL',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 20,
      precoVenda: 33.99,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Formigres Catavento CL',
      quantidade: 18900, // 18,9 m2 em milesimos
      precoUnitario: 33.99,
      precoCustoUnitario: 20,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..carretoReservaAteSaida = true
      ..itens.add(item);

    expect(
      EntregaVendaHelper.quantidadeRomaneioCarga(venda, item),
      18900,
    );
    expect(
      EntregaVendaHelper.quantidadeRomaneioCargaExibicao(venda, item),
      closeTo(18.9, 0.001),
    );
    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioCarga(venda, item),
      '18,9 M2',
    );
    expect(
      EntregaVendaHelper.textoLinhaItemRomaneioCarga(venda, item),
      '18,9 M2 — Formigres Catavento CL',
    );
    expect(
      EntregaVendaHelper.subtotalRomaneioCarga(venda, item),
      closeTo(18.9 * 33.99, 0.02),
    );
  });

  test('romaneio consolidado formata qtd fracionada', () {
    final produto = Produto(
      codigoInterno: 'AREIA',
      nome: 'Areia',
      unidade: 'M3',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 178,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Areia',
      quantidade: 500,
      precoUnitario: 178,
      precoCustoUnitario: 50,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..carretoReservaAteSaida = true
      ..itens.add(item);

    final linhas = RomaneioCargaMerge.montarLinhas([venda]);
    expect(linhas, hasLength(1));
    expect(linhas.first.quantidadeTotal, 500);
    expect(linhas.first.escalaFracionada, isTrue);
    expect(linhas.first.quantidadeTotalTexto, '0,5');
  });

  test('carreto desconta retirada na loja do saldo do motorista', () {
    final produto = Produto(
      codigoInterno: 'TREL',
      nome: 'Trelica H8',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 15,
    );
    final item = ItemVenda(
      nomeProduto: 'Trelica H8',
      quantidade: 30,
      quantidadeJaRetirada: 12,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..carretoReservaAteSaida = false
      ..itens.add(item);

    expect(EntregaVendaHelper.quantidadeRomaneioCarga(venda, item), 18);
    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioComUnidade(venda, item),
      '18 UN',
    );
    expect(EntregaVendaHelper.itensCargaMotorista(venda, [item]), hasLength(1));

    item.quantidadeJaRetirada = 30;
    expect(EntregaVendaHelper.quantidadeRomaneioCarga(venda, item), 0);
    expect(EntregaVendaHelper.itensCargaMotorista(venda, [item]), isEmpty);
  });

  test('30 UN em milesimos exibe 30 UN no motorista (nao 30000)', () {
    final produto = Produto(
      codigoInterno: 'TREL',
      nome: 'Trelica H8',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 15,
      permiteQuantidadeFracionada: false,
    );
    final item = ItemVenda(
      nomeProduto: 'Trelica H8',
      quantidade: 30000,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..itens.add(item);

    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioComUnidade(venda, item),
      '30 UN',
    );
    expect(
      EntregaVendaHelper.quantidadeRomaneioCargaExibicao(venda, item),
      closeTo(30, 0.001),
    );
  });

  test('resolverProduto formata qtd quando ToOne do item vem vazio (LAN)', () {
    final produto = Produto(
      id: 42,
      codigoInterno: 'TREL',
      nome: 'Trelica H8',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 15,
      permiteQuantidadeFracionada: false,
    );
    final item = ItemVenda(
      nomeProduto: 'Trelica H8',
      quantidade: 30000,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.targetId = 42;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..itens.add(item);

    expect(EntregaVendaHelper.produtoItemEntrega(item), isNull);
    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioComUnidade(
        venda,
        item,
        obterProduto: (id) => id == 42 ? produto : null,
      ),
      '30 UN',
    );
    expect(
      EntregaVendaHelper.textoLinhaItemRomaneioCarga(
        venda,
        item,
        obterProduto: (id) => id == 42 ? produto : null,
      ),
      '30 UN — Trelica H8',
    );
    expect(
      EntregaVendaHelper.quantidadeRomaneioCargaExibicao(
        venda,
        item,
        obterProduto: (id) => id == 42 ? produto : null,
      ),
      closeTo(30, 0.001),
    );
  });

  test('metro/trelica fracionada 30 M exibe sem multiplicar por 1000 na UI', () {
    final produto = Produto(
      codigoInterno: 'VIG',
      nome: 'Viga trelicada',
      unidade: 'M',
      quantidadeMinima: 0,
      precoCusto: 20,
      precoVenda: 45,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      nomeProduto: 'Viga trelicada',
      quantidade: 30000,
      precoUnitario: 45,
      precoCustoUnitario: 20,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    )..produto.target = produto;

    final venda = Venda()
      ..status = 'finalizada'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..itens.add(item);

    expect(
      EntregaVendaHelper.textoQuantidadeRomaneioComUnidade(venda, item),
      '30 M',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('legado nao sobrescreve itens mistos', () {
    final venda = Venda(
      status: 'orcamento',
      tipoEntrega: EntregaVendaHelper.tipoMisto,
      formaPagamento: 'dinheiro',
    );
    final a = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 3,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    final b = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 2,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    );
    EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(
      venda,
      itens: [a, b],
    );
    expect(a.tipoEntregaItem, EntregaVendaHelper.tipoRetirada);
    expect(b.tipoEntregaItem, EntregaVendaHelper.tipoRetiradaFutura);
  });

  test('legado nao promove leva agora quando so entregaPendente esta true', () {
    final venda = Venda(
      status: 'orcamento',
      tipoEntrega: EntregaVendaHelper.tipoRetirada,
      entregaPendente: true,
      formaPagamento: 'dinheiro',
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 5,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(
      venda,
      itens: [item],
    );
    expect(item.tipoEntregaItem, EntregaVendaHelper.tipoRetirada);
  });

  test('legado replica cabecalho futura quando todos itens sao padrao retirada', () {
    final venda = Venda(
      status: 'orcamento',
      tipoEntrega: EntregaVendaHelper.tipoRetiradaFutura,
      formaPagamento: 'dinheiro',
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 5,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(
      venda,
      itens: [item],
    );
    expect(item.tipoEntregaItem, EntregaVendaHelper.tipoRetiradaFutura);
  });

  test('tipo efetivo distingue leva agora e retirada futura', () {
    final imediata = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 3,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    final futura = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 2,
      precoUnitario: 50,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    );
    expect(
      EntregaVendaHelper.tipoEfetivoItem(imediata),
      EntregaVendaHelper.tipoRetirada,
    );
    expect(
      EntregaVendaHelper.tipoEfetivoItem(futura),
      EntregaVendaHelper.tipoRetiradaFutura,
    );
  });

  test('resolver tipo venda mista a partir dos itens', () {
    expect(
      EntregaVendaHelper.resolverTipoEntregaVenda([
        EntregaVendaHelper.tipoRetirada,
        EntregaVendaHelper.tipoRetiradaFutura,
      ]),
      EntregaVendaHelper.tipoMisto,
    );
  });

  test('legado com cabecalho carreto nao apaga itens ja mistos', () {
    final venda = Venda(
      status: 'orcamento',
      // Header stale (bug antigo do checkout forçava carreto no cabecalho).
      tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
      formaPagamento: 'dinheiro',
    );
    final leva = ItemVenda(
      nomeProduto: 'A',
      quantidade: 1,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    final futura = ItemVenda(
      nomeProduto: 'B',
      quantidade: 1,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    );
    final carreto = ItemVenda(
      nomeProduto: 'C',
      quantidade: 1,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
    );
    // Simula o que converterOrcamentoParaVenda faz agora.
    venda.tipoEntrega = EntregaVendaHelper.resolverTipoEntregaVenda([
      leva.tipoEntregaItem,
      futura.tipoEntregaItem,
      carreto.tipoEntregaItem,
    ]);
    EntregaVendaHelper.aplicarLegadoTipoUnicoNosItensSeNecessario(
      venda,
      itens: [leva, futura, carreto],
    );
    expect(venda.tipoEntrega, EntregaVendaHelper.tipoMisto);
    expect(leva.tipoEntregaItem, EntregaVendaHelper.tipoRetirada);
    expect(futura.tipoEntregaItem, EntregaVendaHelper.tipoRetiradaFutura);
    expect(carreto.tipoEntregaItem, EntregaVendaHelper.tipoEntregaLoja);
  });

  test('vendaTemItensCarreto prioriza linhas e nao so o cabecalho', () {
    final venda = Venda(
      status: 'finalizada',
      tipoEntrega: EntregaVendaHelper.tipoEntregaLoja,
      formaPagamento: 'dinheiro',
    );
    final leva = ItemVenda(
      nomeProduto: 'A',
      quantidade: 1,
      precoUnitario: 10,
      precoCustoUnitario: 5,
      tipoEntregaItem: EntregaVendaHelper.tipoRetirada,
    );
    expect(
      EntregaVendaHelper.vendaTemItensCarreto(venda, itens: [leva]),
      isFalse,
    );
  });

  test('produto livre reduz com reservado', () {
    final p = Produto(
      codigoInterno: '941',
      nome: 'Cimento',
      estoqueReal: 47,
      estoqueReservado: 2,
      quantidadeMinima: 0,
      precoCusto: 40,
      precoVenda: 50,
      preco1: 54.5,
      preco2: 50,
      preco3: 50,
      ativo: true,
    );
    expect(p.estoqueLivreParaVenda, 45);
  });
}

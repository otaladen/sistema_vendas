import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/entregas/buscar_na_loja.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  Produto produtoUnMilesimos() => Produto(
        codigoInterno: 'TREL',
        nome: 'Trelica H8',
        unidade: 'UN',
        quantidadeMinima: 0,
        precoCusto: 10,
        precoVenda: 15,
        permiteQuantidadeFracionada: false,
      );

  Venda vendaCarreto(ItemVenda item) {
    final venda = Venda()
      ..status = 'finalizada'
      ..statusEntrega = 'saiu_entrega'
      ..tipoEntrega = EntregaVendaHelper.tipoEntregaLoja
      ..itens.add(item);
    return venda;
  }

  test('30 UN em milesimos (30000) exibe 30 UN e aceita so inteiros', () {
    final produto = produtoUnMilesimos();
    final item = ItemVenda(
      id: 10,
      nomeProduto: 'Trelica H8',
      quantidade: 30000,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      lojaOrigemMercadoria: 'outra_loja',
    )..produto.target = produto;

    final venda = vendaCarreto(item);

    expect(BuscarNaLoja.qtdCarga(venda, item), 30000);
    final entrada = BuscarNaLoja.entradaQuantidadeModal(venda, item)!;
    expect(entrada.textoTotalComUnidade, '30 UN');
    expect(entrada.aceitaDecimal, isFalse);
    expect(entrada.armazenadoDe('1'), 1000);
    expect(entrada.armazenadoDe('30'), 30000);
    expect(entrada.armazenadoDe('1,5'), isNull);
    expect(entrada.armazenadoDe('31'), isNull);
  });

  test('6000 armazenados legado UN fracionado exibe 6 UN (caso 6 unidades)', () {
    final produto = Produto(
      codigoInterno: 'ARCO',
      nome: 'Arco',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 15,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      id: 11,
      nomeProduto: 'Arco',
      quantidade: 6000,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      lojaOrigemMercadoria: 'outra_loja',
    )..produto.target = produto;

    final venda = vendaCarreto(item);

    final entrada = BuscarNaLoja.entradaQuantidadeModal(venda, item)!;
    expect(entrada.textoTotalComUnidade, '6 UN');
    expect(entrada.armazenadoDe(entrada.textoTotal), 6000);
  });

  test('selecionar 6 unidades envia valor interno correto ao patio', () {
    final produto = produtoUnMilesimos();
    final item = ItemVenda(
      id: 12,
      nomeProduto: 'Trelica H8',
      quantidade: 30000,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      precoUnitario: 15,
      precoCustoUnitario: 10,
      lojaOrigemMercadoria: 'outra_loja',
    )..produto.target = produto;

    final venda = vendaCarreto(item);

    expect(
      BuscarNaLoja.armazenadoDeQuantidadeExibicao(venda, item, 6),
      6000,
    );
    expect(
      BuscarNaLoja.entradaQuantidadeModal(venda, item)!.inicialArmazenado,
      30000,
    );
  });

  test('M2 fracionado aceita decimal na unidade de venda', () {
    final produto = Produto(
      codigoInterno: 'FORM',
      nome: 'Piso',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 20,
      permiteQuantidadeFracionada: true,
    );
    final item = ItemVenda(
      id: 13,
      nomeProduto: 'Piso',
      quantidade: 2000,
      tipoEntregaItem: EntregaVendaHelper.tipoEntregaLoja,
      precoUnitario: 20,
      precoCustoUnitario: 10,
      lojaOrigemMercadoria: 'outra_loja',
    )..produto.target = produto;

    final venda = vendaCarreto(item);

    final entrada = BuscarNaLoja.entradaQuantidadeModal(venda, item)!;
    expect(entrada.textoTotalComUnidade, '2 M²');
    expect(entrada.aceitaDecimal, isTrue);
    expect(entrada.armazenadoDe('0,5'), 500);
    expect(
      BuscarNaLoja.armazenadoDeQuantidadeExibicao(venda, item, 1.5),
      1500,
    );
  });
}

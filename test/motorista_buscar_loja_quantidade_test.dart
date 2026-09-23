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

  test('30 UN em milesimos (30000) exibe 30 UN no modal e opcoes 1..30', () {
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
    expect(
      BuscarNaLoja.textoIntroducaoModal(venda, item),
      contains('De 30 UN'),
    );

    final opcoes = BuscarNaLoja.opcoesQuantidadeModal(venda, item);
    expect(opcoes, hasLength(30));
    expect(opcoes.first.rotulo, '1 UN de 30 UN');
    expect(opcoes.last.armazenado, 30000);
    expect(opcoes.last.rotulo, 'Todos (30 UN)');
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

    expect(
      BuscarNaLoja.textoIntroducaoModal(venda, item),
      contains('De 6 UN'),
    );
    final opcoes = BuscarNaLoja.opcoesQuantidadeModal(venda, item);
    expect(opcoes, hasLength(6));
    expect(opcoes.last.armazenado, 6000);
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
      BuscarNaLoja.opcoesQuantidadeModal(venda, item).last.armazenado,
      30000,
    );
  });

  test('M2 fracionado gera opcoes em 0,5 na unidade de venda', () {
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

    expect(
      BuscarNaLoja.textoIntroducaoModal(venda, item),
      contains('De 2 M2'),
    );

    final opcoes = BuscarNaLoja.opcoesQuantidadeModal(venda, item);
    expect(opcoes.first.rotulo, '0,5 M2 de 2 M2');
    expect(opcoes.first.armazenado, 500);
    expect(opcoes.last.armazenado, 2000);

    expect(
      BuscarNaLoja.armazenadoDeQuantidadeExibicao(venda, item, 1.5),
      1500,
    );
  });
}

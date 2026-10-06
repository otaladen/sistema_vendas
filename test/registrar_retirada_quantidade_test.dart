import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/entrega_venda_helper.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto produtoM2() => Produto(
        codigoInterno: '58010',
        nome: 'Isadora 58010',
        unidade: 'M2',
        quantidadeMinima: 0,
        precoCusto: 10,
        precoVenda: 20,
        permiteQuantidadeFracionada: true,
      );

  ItemVenda itemM2({required int quantidadeArmazenada}) {
    final item = ItemVenda(
      nomeProduto: 'Isadora 58010',
      quantidade: quantidadeArmazenada,
      precoUnitario: 20,
      precoCustoUnitario: 10,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    )..produto.target = produtoM2();
    return item;
  }

  const pendenteM2 = 10720; // 10,72 m²

  test('saldo pendente exibe 10,72 M2 (nao 10720 un.)', () {
    final item = itemM2(quantidadeArmazenada: pendenteM2);
    expect(
      EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: pendenteM2,
      ),
      '10,72 M2',
    );
    expect(
      EntregaVendaHelper.textoEntradaQuantidadeRetirada(
        item,
        quantidadeArmazenada: pendenteM2,
      ),
      '10,72',
    );
  });

  test('parse aceita 10,72 e persiste milesimos', () {
    final item = itemM2(quantidadeArmazenada: pendenteM2);
    expect(
      EntregaVendaHelper.retiradaEntradaFracionada(
        item,
        quantidadeArmazenadaReferencia: pendenteM2,
      ),
      isTrue,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '10,72',
        pendenteArmazenado: pendenteM2,
      ),
      pendenteM2,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '10.72',
        pendenteArmazenado: pendenteM2,
      ),
      pendenteM2,
    );
  });

  test('parse rejeita acima do pendente real', () {
    final item = itemM2(quantidadeArmazenada: pendenteM2);
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '10,73',
        pendenteArmazenado: pendenteM2,
      ),
      isNull,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '10720',
        pendenteArmazenado: pendenteM2,
      ),
      isNull,
    );
  });

  test('produto UN inteiro mantem entrada e limite em unidades', () {
    final produto = Produto(
      codigoInterno: 'PAR',
      nome: 'Parafuso',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 1,
      precoVenda: 2,
    );
    const pendente = 5;
    final item = ItemVenda(
      nomeProduto: 'Parafuso',
      quantidade: pendente,
      precoUnitario: 2,
      precoCustoUnitario: 1,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    )..produto.target = produto;

    expect(
      EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: pendente,
      ),
      '5 UN',
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '3',
        pendenteArmazenado: pendente,
      ),
      3,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '3,5',
        pendenteArmazenado: pendente,
      ),
      isNull,
    );
  });

  test('baixa parcial fracionada grava milesimos corretos', () {
    final item = itemM2(quantidadeArmazenada: pendenteM2);
    final q = EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
      item,
      texto: '2,5',
      pendenteArmazenado: pendenteM2,
    );
    expect(q, QuantidadeVendaUtil.paraArmazenamento(2.5, fracionada: true));
  });

  Produto produtoCimentoSc() => Produto(
        codigoInterno: '939',
        nome: 'Cimento Poty 50kg',
        unidade: 'SC',
        quantidadeMinima: 0,
        precoCusto: 40,
        precoVenda: 55,
      );

  ItemVenda itemSc({
    required int quantidadeArmazenada,
    int escalaQuantidade = ItemVenda.escalaQuantidadeLegado,
  }) {
    final item = ItemVenda(
      nomeProduto: 'Cimento Poty 50kg',
      quantidade: quantidadeArmazenada,
      precoUnitario: 55,
      precoCustoUnitario: 40,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
      escalaQuantidade: escalaQuantidade,
    )..produto.target = produtoCimentoSc();
    return item;
  }

  test('1 SC pendente inteiro confirma entrada 1, 1,0 e 1.0', () {
    const pendenteLiteral = 1;
    final item = itemSc(
      quantidadeArmazenada: pendenteLiteral,
      escalaQuantidade: ItemVenda.escalaQuantidadeLiteral,
    );
    expect(
      EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: pendenteLiteral,
      ),
      '1 SC',
    );
    expect(
      EntregaVendaHelper.retiradaEntradaFracionada(
        item,
        quantidadeArmazenadaReferencia: pendenteLiteral,
      ),
      isFalse,
    );
    for (final texto in ['1', '1,0', '1.0']) {
      expect(
        EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
          item,
          texto: texto,
          pendenteArmazenado: pendenteLiteral,
        ),
        pendenteLiteral,
        reason: 'texto=$texto',
      );
    }
    final sugerido = EntregaVendaHelper.textoEntradaQuantidadeRetirada(
      item,
      quantidadeArmazenada: pendenteLiteral,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: sugerido,
        pendenteArmazenado: pendenteLiteral,
      ),
      pendenteLiteral,
    );
  });

  test('1 SC em milésimos (1000) aceita retirar tudo com texto sugerido', () {
    const pendenteMilesimos = 1000;
    final item = itemSc(
      quantidadeArmazenada: pendenteMilesimos,
      escalaQuantidade: ItemVenda.escalaQuantidadeMilesimos,
    );
    expect(
      EntregaVendaHelper.textoQuantidadeRetiradaComUnidade(
        item,
        quantidadeArmazenada: pendenteMilesimos,
      ),
      '1 SC',
    );
    final sugerido = EntregaVendaHelper.textoEntradaQuantidadeRetirada(
      item,
      quantidadeArmazenada: pendenteMilesimos,
    );
    expect(sugerido, '1');
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: sugerido,
        pendenteArmazenado: pendenteMilesimos,
      ),
      pendenteMilesimos,
    );
  });

  test('estoque fracionado no cadastro nao forca milésimos em saldo literal', () {
    final produto = Produto(
      codigoInterno: 'KG-SC',
      nome: 'Produto KG/SC',
      unidade: 'KG',
      unidadeCompra: 'SC',
      quantidadePorEmbalagem: 50,
      permiteQuantidadeFracionada: true,
      quantidadeMinima: 0,
      precoCusto: 1,
      precoVenda: 2,
    );
    const pendente = 1;
    final item = ItemVenda(
      nomeProduto: 'Produto KG/SC',
      quantidade: pendente,
      precoUnitario: 2,
      precoCustoUnitario: 1,
      tipoEntregaItem: EntregaVendaHelper.tipoRetiradaFutura,
    )..produto.target = produto;

    expect(
      EntregaVendaHelper.retiradaEntradaFracionada(
        item,
        quantidadeArmazenadaReferencia: pendente,
      ),
      isFalse,
    );
    expect(
      EntregaVendaHelper.parseQuantidadeRetiradaEntrada(
        item,
        texto: '1',
        pendenteArmazenado: pendente,
      ),
      pendente,
    );
  });
}

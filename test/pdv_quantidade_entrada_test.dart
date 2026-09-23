import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produtoUn({String unidade = 'UN'}) => Produto(
      id: 1,
      codigoInterno: 'BLOCO',
      nome: 'Bloco Grande',
      unidade: unidade,
      quantidadeMinima: 0,
      precoCusto: 10,
      precoVenda: 2.5,
      permiteQuantidadeFracionada: false,
    );

Produto _produtoM2() => Produto(
      id: 2,
      codigoInterno: 'PISO',
      nome: 'Piso',
      unidade: 'M2',
      quantidadeMinima: 0,
      precoCusto: 30,
      precoVenda: 45,
      permiteQuantidadeFracionada: true,
    );

void main() {
  test('1400 em produto UN vira 1400 unidades e subtotal correto', () {
    final produto = _produtoUn();
    const preco = 2.5;
    final q = QuantidadeVendaUtil.parseQuantidadeEntradaPdv(
      '1400',
      aceitaDecimal: true,
    );
    expect(q, closeTo(1400.0, 0.0001));

    final arm = QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
      produto: produto,
      quantidadeVenda: q!,
      emUnidadeCompra: false,
    );
    expect(arm.gravadoEmMilesimosPdv, isFalse);
    expect(arm.armazenado, 1400);
    expect(
      ProdutoEmbalagem.leituraUsaEscalaFracionada(produto, arm.armazenado),
      isFalse,
    );

    final qEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: arm.armazenado,
    );
    expect(qEfetiva, closeTo(1400.0, 0.0001));
    expect(qEfetiva * preco, closeTo(3500.0, 0.01));
  });

  test('18,9 em produto M2 vira 18,9 no carrinho', () {
    final produto = _produtoM2();
    final q = QuantidadeVendaUtil.parseQuantidadeEntradaPdv(
      '18,9',
      aceitaDecimal: true,
    );
    expect(q, closeTo(18.9, 0.0001));

    final arm = QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
      produto: produto,
      quantidadeVenda: q!,
      emUnidadeCompra: false,
    );
    expect(arm.gravadoEmMilesimosPdv, isTrue);
    expect(arm.armazenado, 18900);

    final qEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: arm.armazenado,
    );
    expect(qEfetiva, closeTo(18.9, 0.0001));
  });

  test('1,4 em produto UN fracionado no PDV vira 1,4 (1400 milésimos)', () {
    final produto = _produtoUn();
    final q = QuantidadeVendaUtil.parseQuantidadeEntradaPdv(
      '1,4',
      aceitaDecimal: true,
    );
    expect(q, closeTo(1.4, 0.0001));

    final arm = QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
      produto: produto,
      quantidadeVenda: q!,
      emUnidadeCompra: false,
    );
    expect(arm.gravadoEmMilesimosPdv, isTrue);
    expect(arm.armazenado, 1400);

    final qEfetivaComFlag = QuantidadeVendaUtil.valorExibicao(
      arm.armazenado,
      fracionada: true,
    );
    expect(qEfetivaComFlag, closeTo(1.4, 0.0001));
  });
}

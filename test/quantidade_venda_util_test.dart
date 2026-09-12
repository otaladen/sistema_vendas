import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('parseQuantidadeTextoCarrinho PT-BR na coluna QTD', () {
    expect(
      QuantidadeVendaUtil.parseQuantidadeTextoCarrinho('0,50'),
      closeTo(0.5, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaCarrinho('0,50', aceitaDecimal: true),
      closeTo(0.5, 0.0001),
    );
    final produto = Produto(
      id: 10,
      codigoInterno: 'TUBO',
      nome: 'Tubo',
      unidade: 'M',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 85,
      permiteQuantidadeFracionada: true,
    );
    expect(
      QuantidadeVendaUtil.armazenarQuantidadeVendaNoCarrinho(
        produto: produto,
        quantidadeVenda: 0.5,
        emUnidadeCompra: false,
      ).armazenado,
      500,
    );
    expect(
      QuantidadeVendaUtil.valorExibicao(
        500,
        fracionada: true,
      ),
      closeTo(0.5, 0.0001),
    );
  });

  test('parseEntradaPdv aceita quantidades fracionadas PT-BR', () {
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('0,50', fracionada: true),
      closeTo(0.5, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('0.5', fracionada: true),
      closeTo(0.5, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('1,5', fracionada: true),
      closeTo(1.5, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('1,00', fracionada: true),
      closeTo(1.0, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('500', fracionada: true),
      closeTo(500.0, 0.0001),
    );
  });

  test('parseEntradaPdv aceita duas casas (5,75)', () {
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('5,75', fracionada: true),
      closeTo(5.75, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('5.75', fracionada: true),
      closeTo(5.75, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.paraArmazenamento(5.75, fracionada: true),
      5750,
    );
    expect(
      QuantidadeVendaUtil.formatarExibicao(5.75, fracionada: true),
      '5,75',
    );
  });

  test('PDV aceita decimal sem flag do cadastro', () {
    expect(
      QuantidadeVendaUtil.parseEntradaPdv('4,50', fracionada: true),
      closeTo(4.5, 0.0001),
    );
    expect(
      QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
        emUnidadeCompra: false,
        quantidadeVenda: 4.5,
      ),
      isTrue,
    );
    expect(
      QuantidadeVendaUtil.paraArmazenamento(4.5, fracionada: true),
      4500,
    );
    expect(
      QuantidadeVendaUtil.armazenadoEmMilesimos(4500),
      isTrue,
    );
    expect(
      QuantidadeVendaUtil.armazenadoEmMilesimos(5),
      isFalse,
    );
    expect(
      QuantidadeVendaUtil.pdvArmazenaEmMilesimos(
        emUnidadeCompra: false,
        quantidadeVenda: 107,
      ),
      isFalse,
    );
  });

  test('textoQuantidadeValido aceita ate 3 casas', () {
    expect(
      QuantidadeVendaUtil.textoQuantidadeValido('5,75', fracionada: true),
      isTrue,
    );
    expect(
      QuantidadeVendaUtil.textoQuantidadeValido('5,755', fracionada: true),
      isTrue,
    );
    expect(
      QuantidadeVendaUtil.textoQuantidadeValido('5,7555', fracionada: true),
      isFalse,
    );
    expect(
      QuantidadeVendaUtil.textoQuantidadeValido('5,7', fracionada: false),
      isFalse,
    );
  });

  test('paraEstoqueInteiro fracionada 0,24 m³ nao vira zero', () {
    final produto = Produto(
      id: 1,
      codigoInterno: 'AREIA',
      nome: 'Areia',
      unidade: 'M3',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
      permiteQuantidadeFracionada: true,
    );
    final arm = QuantidadeVendaUtil.paraArmazenamento(
      0.24,
      fracionada: true,
    );
    expect(arm, 240);
    expect(QuantidadeVendaUtil.paraEstoqueInteiro(produto, arm), 1);
  });

  test('500 milesimos exibe 0,5 sem flag de cadastro (tubo PDV)', () {
    final produto = Produto(
      id: 3,
      codigoInterno: 'TUBO',
      nome: 'Tubo',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 85,
      permiteQuantidadeFracionada: false,
    );
    expect(produto.pdvPermiteQuantidadeDecimal, isTrue);
    const armazenado = 500;
    expect(
      QuantidadeVendaUtil.armazenadoEmMilesimos(armazenado),
      isTrue,
    );
    expect(
      ProdutoEmbalagem.leituraUsaEscalaFracionada(produto, armazenado),
      isTrue,
    );
    final qEfetiva = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: armazenado,
    );
    expect(qEfetiva, closeTo(0.5, 0.0001));
    expect(qEfetiva * produto.precoVenda, closeTo(42.5, 0.01));
    expect(QuantidadeVendaUtil.armazenadoEmMilesimos(5), isFalse);
  });

  test('paraEstoqueInteiro inteira continua igual', () {
    final produto = Produto(
      id: 2,
      codigoInterno: 'CIM',
      nome: 'Cimento',
      unidade: 'SC',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    expect(QuantidadeVendaUtil.paraEstoqueInteiro(produto, 2), 2);
  });
}

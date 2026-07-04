import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/produto_embalagem.dart';
import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto pisoCx() => Produto(
        id: 1,
        codigoInterno: '008858',
        nome: 'Piso teste',
        unidade: 'M2',
        unidadeCompra: 'CX',
        quantidadePorEmbalagem: 2.63,
        embalagemMultiplica: true,
        quantidadeMinima: 0,
        precoCusto: 0,
        precoVenda: 32.99,
        preco1: 32.99,
        permiteQuantidadeFracionada: true,
      );

  test('1 CX converte para 2,63 m2 no subtotal', () {
    final produto = pisoCx();
    final m2 = ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
      produto: produto,
      quantidadeComercial: 1,
    );
    expect(m2, closeTo(2.63, 0.001));
    expect(m2 * produto.preco1, closeTo(86.76, 0.01));
  });

  test('quantidadeArmazenadaItemVenda grava m2 fracionado', () {
    final produto = pisoCx();
    final armazenado = ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
      produto: produto,
      quantidadeDigitada: 1,
      emUnidadeCompra: true,
    );
    expect(armazenado, QuantidadeVendaUtil.paraArmazenamento(2.63, fracionada: true));
  });

  test('rotuloQuantidadeCarrinho exibe m2 exato da caixa', () {
    final produto = pisoCx();
    expect(
      ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: 1,
        emUnidadeCompra: true,
      ),
      '1 CX (= 2,63 M2)',
    );
  });

  test('formatacao decimal mesmo sem venda fracionada no cadastro', () {
    final produto = Produto(
      id: 2,
      codigoInterno: '008858',
      nome: 'Piso teste',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 32.99,
      preco1: 32.99,
      permiteQuantidadeFracionada: false,
    );
    expect(
      ProdutoEmbalagem.formatarQuantidadeUnidadeVenda(produto, 2.63),
      '2,63',
    );
    expect(
      ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: 1,
        emUnidadeCompra: true,
      ),
      '1 CX (= 2,63 M2)',
    );
    expect(
      ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
        produto: produto,
        quantidadeDigitada: 1,
        emUnidadeCompra: true,
      ),
      QuantidadeVendaUtil.paraArmazenamento(2.63, fracionada: true),
    );
  });

  test('quantidadeVendaEfetivaItem le m2 armazenado sem fracionada no cadastro', () {
    final produto = Produto(
      id: 3,
      codigoInterno: '008858',
      nome: 'Piso Arielle',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 32.99,
      preco1: 32.99,
      permiteQuantidadeFracionada: false,
    );
    final armazenado = ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
      produto: produto,
      quantidadeDigitada: 1,
      emUnidadeCompra: true,
    );
    final qtd = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: armazenado,
    );
    expect(qtd, closeTo(2.63, 0.001));
    expect(qtd * produto.preco1, closeTo(86.76, 0.01));
  });

  test('quantidadeVendaEfetivaItem 3 CX', () {
    final produto = Produto(
      id: 4,
      codigoInterno: '008858',
      nome: 'Piso Arielle',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 32.99,
      preco1: 32.99,
      permiteQuantidadeFracionada: false,
    );
    final armazenado = ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
      produto: produto,
      quantidadeDigitada: 3,
      emUnidadeCompra: true,
    );
    final qtd = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
      produto: produto,
      quantidadeArmazenada: armazenado,
    );
    expect(qtd, closeTo(7.89, 0.001));
    expect(qtd * produto.preco1, closeTo(260.29, 0.05));
  });

  test('quantidadeCarrinhoDeItemPersistido reconverte 5260 para 2 CX', () {
    final produto = Produto(
      id: 5,
      codigoInterno: '008858',
      nome: 'Piso Arielle',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 32.99,
      preco1: 32.99,
      permiteQuantidadeFracionada: false,
    );
    final carrinho = ProdutoEmbalagem.quantidadeCarrinhoDeItemPersistido(
      produto: produto,
      quantidadeArmazenada: 5260,
    );
    expect(carrinho.emUnidadeCompra, isTrue);
    expect(carrinho.quantidadeDigitada, 2);
    final subtotal = ProdutoEmbalagem.quantidadeVendaEfetivaItem(
          produto: produto,
          quantidadeArmazenada: 5260,
        ) *
        produto.preco1;
    expect(subtotal, closeTo(173.53, 0.05));
  });

  test('quantidadeCarrinhoDeItemPersistido ida e volta 1 CX', () {
    final produto = Produto(
      id: 6,
      codigoInterno: '008858',
      nome: 'Piso Arielle',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      embalagemMultiplica: true,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 32.99,
      preco1: 32.99,
      permiteQuantidadeFracionada: false,
    );
    final armazenado = ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
      produto: produto,
      quantidadeDigitada: 1,
      emUnidadeCompra: true,
    );
    final carrinho = ProdutoEmbalagem.quantidadeCarrinhoDeItemPersistido(
      produto: produto,
      quantidadeArmazenada: armazenado,
    );
    expect(carrinho.emUnidadeCompra, isTrue);
    expect(carrinho.quantidadeDigitada, 1);
    expect(
      ProdutoEmbalagem.quantidadeArmazenadaItemVenda(
        produto: produto,
        quantidadeDigitada: carrinho.quantidadeDigitada,
        emUnidadeCompra: carrinho.emUnidadeCompra,
      ),
      armazenado,
    );
  });
}

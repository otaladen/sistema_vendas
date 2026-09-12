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

  test('unidadeEstoqueDeQuantidadeArmazenada 4 CX baixa m2 exato', () {
    final produto = Produto(
      id: 8,
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
    expect(
      ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: 10520,
      ),
      10520,
    );
    expect(
      ProdutoEmbalagem.unidadeEstoqueDeQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: 2630,
      ),
      2630,
    );
  });

  test('formatarEstoque exibe m2 fracionado no cadastro e PDV', () {
    final produto = pisoCx()..estoqueReal = 144620;
    expect(
      ProdutoEmbalagem.formatarEstoque(produto, produto.estoqueReal),
      '144,62',
    );
    expect(
      ProdutoEmbalagem.formatarEstoqueDetalhado(produto, produto.estoqueReal),
      contains('144,62'),
    );
    expect(produto.estoqueExibicao, closeTo(144.62, 0.001));
  });

  test('formatarEstoque sinaliza saldo armazenado absurdo', () {
    final produto = pisoCx()..estoqueReal = -10002010000;
    expect(
      ProdutoEmbalagem.formatarEstoque(produto, produto.estoqueReal),
      'Saldo invalido',
    );
    expect(
      ProdutoEmbalagem.formatarEstoque(
        produto,
        produto.estoqueReal,
        comUnidade: true,
      ),
      'Saldo invalido M2',
    );
  });

  test('estoque legado inteiro migra na leitura para escala', () {
    final produto = pisoCx()..estoqueReal = 145;
    expect(produto.estoqueExibicao, 145);
    ProdutoEmbalagem.garantirEstoqueEmEscalaNoProduto(produto);
    expect(produto.estoqueReal, 145000);
    expect(produto.estoqueExibicao, 145);
  });

  test('parseEstoqueEntrada grava milésimos para piso CX', () {
    final produto = pisoCx();
    expect(
      ProdutoEmbalagem.parseEstoqueEntrada('144,62', produto),
      144620,
    );
  });

  test('quantidadeNotaParaEstoque NF-e 10 CX grava m2 exato', () {
    final produto = pisoCx();
    expect(
      ProdutoEmbalagem.quantidadeNotaParaUnidadeVenda(
        quantidadeComercial: 10,
        fator: 2.63,
        embalagemMultiplica: true,
      ),
      closeTo(26.3, 0.001),
    );
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 10,
        fator: 2.63,
        embalagemMultiplica: true,
        produto: produto,
        unidadeComercial: 'CX',
        unidadeInterna: 'M2',
      ),
      26300,
    );
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 1,
        fator: 2.63,
        embalagemMultiplica: true,
        produto: produto,
      ),
      2630,
    );
  });

  test('quantidadeNotaParaEstoque NF-e produto novo CX/M2 sem cadastro', () {
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 4,
        fator: 2.63,
        embalagemMultiplica: true,
        unidadeComercial: 'CX',
        unidadeInterna: 'M2',
      ),
      10520,
    );
  });

  test('quantidadeNotaParaEstoque NF-e unidade inteira continua arredondando', () {
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 10,
        fator: 1,
        embalagemMultiplica: true,
        unidadeComercial: 'SC',
        unidadeInterna: 'SC',
      ),
      10,
    );
  });

  test('quantidadeNotaParaEstoque NF-e PC1/UN fator 1 nao multiplica por 1000', () {
    // Bug real: arco de serra qCom=6 PC1 virava Entrada 6000.
    expect(ProdutoEmbalagem.normalizarUnidade('PC1'), 'UN');
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 6,
        fator: 1,
        embalagemMultiplica: true,
        unidadeComercial: 'PC1',
        unidadeInterna: 'UN',
      ),
      6,
    );
    expect(
      ProdutoEmbalagem.notaExigeEscalaEstoque(
        quantidadeUnidadeVenda: 6,
        fator: 1,
        unidadeComercial: 'PC1',
        unidadeInterna: 'UN',
      ),
      isFalse,
    );
  });

  test('quantidadeNotaParaEstoque NF-e RL100/UN fator 1 permanece inteiro', () {
    expect(
      ProdutoEmbalagem.quantidadeNotaParaEstoque(
        quantidadeComercial: 1,
        fator: 1,
        embalagemMultiplica: true,
        unidadeComercial: 'RL100',
        unidadeInterna: 'UN',
      ),
      1,
    );
  });

  test('textoQuantidadeArmazenada exibe m2 e nao escala bruta no caixa', () {
    final produto = Produto(
      id: 7,
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
    expect(
      ProdutoEmbalagem.textoQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: 10520,
      ),
      '4 CX (= 10,52 M2)',
    );
    expect(
      ProdutoEmbalagem.passoQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: 10520,
      ),
      QuantidadeVendaUtil.paraArmazenamento(2.63, fracionada: true),
    );
  });

  test('passo fracionado no PDV e 0,01', () {
    final produto = Produto(
      id: 8,
      codigoInterno: 'AREIA',
      nome: 'Areia',
      unidade: 'M3',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 10,
      permiteQuantidadeFracionada: true,
    );
    expect(
      ProdutoEmbalagem.passoQuantidadeArmazenada(
        produto: produto,
        quantidadeArmazenada: QuantidadeVendaUtil.paraArmazenamento(
          5.7,
          fracionada: true,
        ),
      ),
      QuantidadeVendaUtil.passoFracionadoArmazenado,
    );
    expect(QuantidadeVendaUtil.passoFracionadoArmazenado, 10);
  });

  test('valorMediaDiariaExibicao converte milésimos em m2/dia', () {
    final produto = pisoCx()..vendaMediaDiaria = 2410.33;
    expect(
      ProdutoEmbalagem.valorMediaDiariaExibicao(produto, 2410.33),
      closeTo(2.41033, 0.0001),
    );
    expect(
      ProdutoEmbalagem.formatarMediaDiaria(produto, 2410.33, comUnidade: true),
      '2,41 M2',
    );
  });

  test('valorMediaDiariaExibicao preserva media ja na unidade de venda', () {
    final produto = pisoCx()..vendaMediaDiaria = 2.41;
    expect(
      ProdutoEmbalagem.valorMediaDiariaExibicao(produto, 2.41),
      closeTo(2.41, 0.001),
    );
  });

  test('PDV le 0,50 (500) sem venda fracionada no cadastro', () {
    final produto = Produto(
      id: 10,
      codigoInterno: 'TUBO',
      nome: 'Tubo',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 50,
      precoVenda: 85,
      permiteQuantidadeFracionada: false,
    );
    const armazenado = 500;
    expect(
      ProdutoEmbalagem.leituraUsaEscalaFracionada(produto, armazenado),
      isTrue,
    );
    expect(
      ProdutoEmbalagem.quantidadeVendaEfetivaItem(
        produto: produto,
        quantidadeArmazenada: armazenado,
      ),
      closeTo(0.5, 0.001),
    );
    expect(0.5 * produto.precoVenda, closeTo(42.5, 0.01));
  });

  test('PDV le 4,50 persistido sem flag de venda fracionada', () {
    final produto = Produto(
      id: 9,
      codigoInterno: 'PARAF',
      nome: 'Parafuso',
      unidade: 'UN',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 1,
      permiteQuantidadeFracionada: false,
    );
    const armazenado = 4500;
    expect(
      ProdutoEmbalagem.leituraUsaEscalaFracionada(produto, armazenado),
      isTrue,
    );
    expect(
      ProdutoEmbalagem.quantidadeVendaEfetivaItem(
        produto: produto,
        quantidadeArmazenada: armazenado,
      ),
      closeTo(4.5, 0.001),
    );
    expect(
      ProdutoEmbalagem.rotuloQuantidadeCarrinho(
        produto: produto,
        quantidadeDigitada: armazenado,
        emUnidadeCompra: false,
      ),
      '4,5 UN',
    );
  });
}

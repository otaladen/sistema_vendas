import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/reajuste_preco_lote.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produtoTeste({
  double preco1 = 10,
  double preco2 = 9,
  double precoCusto = 5,
  double custoMedio = 6,
}) {
  return Produto(
    codigoInterno: 'SKU1',
    nome: 'Produto teste',
    quantidadeMinima: 0,
    precoCusto: precoCusto,
    custoMedio: custoMedio,
    preco1: preco1,
    preco2: preco2,
    precoVenda: preco1,
  );
}

void main() {
  test('percentual +10% sobre preco1', () {
    final p = _produtoTeste(preco1: 100);
    const params = ReajustePrecoParametros(
      modo: ReajustePrecoModo.percentualSobrePrecoAtual,
      tabelas: {ReajusteTabelaPreco.preco1},
      percentualSobrePreco: 10,
    );
    final linha = ReajustePrecoLoteService.simularProduto(p, params);
    expect(linha.seraAlterado, isTrue);
    expect(linha.preco1Depois, 110);
  });

  test('bloqueia preco abaixo do custo', () {
    final p = _produtoTeste(preco1: 6, precoCusto: 5);
    const params = ReajustePrecoParametros(
      modo: ReajustePrecoModo.percentualSobrePrecoAtual,
      tabelas: {ReajusteTabelaPreco.preco1},
      percentualSobrePreco: -50,
      naoAlterarSeAbaixoDoCusto: true,
    );
    final linha = ReajustePrecoLoteService.simularProduto(p, params);
    expect(linha.seraAlterado, isFalse);
    expect(linha.motivoIgnorado, contains('custo'));
  });

  test('margem fixa recalcula a partir do custo medio', () {
    final p = _produtoTeste(preco1: 50, precoCusto: 5, custoMedio: 10);
    const params = ReajustePrecoParametros(
      modo: ReajustePrecoModo.margemFixaSobreCusto,
      tabelas: {ReajusteTabelaPreco.preco1},
      margemPercentual: 50,
      baseCusto: ReajusteBaseCusto.custoMedio,
    );
    final linha = ReajustePrecoLoteService.simularProduto(p, params);
    expect(linha.seraAlterado, isTrue);
    expect(linha.preco1Depois, 20);
  });

  test('arredondamento dezena 90', () {
    expect(
      ReajustePrecoLoteService.arredondarPreco(
        12.34,
        ReajusteArredondamento.dezena90,
      ),
      12.90,
    );
    expect(
      ReajustePrecoLoteService.arredondarPreco(
        12.95,
        ReajusteArredondamento.dezena90,
      ),
      13.90,
    );
  });

  test('exige autorizacao em variacao alta', () {
    final p = _produtoTeste(preco1: 100);
    const params = ReajustePrecoParametros(
      modo: ReajustePrecoModo.percentualSobrePrecoAtual,
      tabelas: {ReajusteTabelaPreco.preco1},
      percentualSobrePreco: 20,
      percentualAbsolutoRequerAutorizacao: 15,
    );
    final linha = ReajustePrecoLoteService.simularProduto(p, params);
    expect(linha.exigeAutorizacaoGerente, isTrue);
  });
}

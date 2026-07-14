import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/ui/estoque/estoque_lista_metricas.dart';

void main() {
  Produto base({
    double custo = 10,
    double custoMedio = 0,
    double precoVenda = 20,
    double preco2 = 0,
    int estoqueReal = 100,
    int estoqueReservado = 20,
    double media = 5,
  }) {
    return Produto(
      codigoInterno: '1',
      nome: 'Teste',
      precoCusto: custo,
      custoMedio: custoMedio,
      precoVenda: precoVenda,
      preco2: preco2,
      estoqueReal: estoqueReal,
      estoqueReservado: estoqueReservado,
      quantidadeMinima: 0,
    )..vendaMediaDiaria = media;
  }

  test('custo exibicao prioriza custo medio', () {
    final p = base(custo: 10, custoMedio: 12);
    expect(EstoqueListaMetricas.custoExibicao(p), 12);
  });

  test('margem usa custo exibicao e preco a vista', () {
    final p = base(custo: 10, precoVenda: 25, preco2: 20);
    expect(EstoqueListaMetricas.margemPercentual(p), 50);
    expect(EstoqueListaMetricas.formatarMargem(p), '50.0%');
  });

  test('cobertura em dias com estoque livre', () {
    final p = base(estoqueReal: 100, estoqueReservado: 20, media: 4);
    expect(EstoqueListaMetricas.coberturaDias(p), 20);
    expect(EstoqueListaMetricas.formatarCobertura(p), '20d');
  });

  test('cobertura sem giro retorna traco com estoque', () {
    final p = base(media: 0, estoqueReal: 5, estoqueReservado: 0);
    expect(EstoqueListaMetricas.coberturaDias(p), isNull);
    expect(EstoqueListaMetricas.formatarCobertura(p), '—');
  });

  test('valor em estoque usa quantidade de exibicao (fracionado)', () {
    final p = Produto(
      codigoInterno: 'CX1',
      nome: 'Piso',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.5,
      permiteQuantidadeFracionada: true,
      precoCusto: 10,
      precoVenda: 20,
      estoqueReal: 10000, // 10,00 m2
      quantidadeMinima: 5,
    );
    // 10 m2 * R$ 10 = R$ 100 (nao 10000*10)
    expect(EstoqueListaMetricas.contribuicaoValorEstoque(p), closeTo(100, 0.01));
    expect(EstoqueListaMetricas.abaixoDoMinimo(p), isFalse);
  });

  test('abaixo do minimo compara unidade de venda', () {
    final p = Produto(
      codigoInterno: 'CX2',
      nome: 'Piso baixo',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.5,
      permiteQuantidadeFracionada: true,
      precoCusto: 10,
      precoVenda: 20,
      estoqueReal: 3000, // 3 m2
      quantidadeMinima: 5,
    );
    expect(p.estoqueExibicao, closeTo(3, 0.001));
    expect(EstoqueListaMetricas.abaixoDoMinimo(p), isTrue);
  });
}

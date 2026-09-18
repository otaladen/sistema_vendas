import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/nfe_revisao_preco.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto produto({
    int id = 1,
    double custo = 10,
    double venda = 15,
    String codigo = 'SKU-1',
    String nome = 'Cimento 50kg',
  }) {
    return Produto(
      id: id,
      codigoInterno: codigo,
      nome: nome,
      quantidadeMinima: 0,
      precoCusto: custo,
      precoVenda: venda,
    );
  }

  test('sugerido aplica markup cadastrado sobre o custo novo', () {
    final item = NfeRevisaoPrecoCalculo.deProduto(
      produto: produto(),
      custoNovo: 12,
      margemMinimaPadrao: 20,
    );
    expect(item.margemLucroCadastrada, closeTo(50, 0.01));
    expect(item.precoVendaSugerido, closeTo(18, 0.01));
    expect(item.custoAumentou, isTrue);
    expect(item.precoVendaAtual, 15);
    expect(item.custoAntigo, 10);
    expect(item.custoNovo, 12);
  });

  test('sem preco de venda usa margem minima da loja', () {
    final item = NfeRevisaoPrecoCalculo.deProduto(
      produto: produto(custo: 0, venda: 0),
      custoNovo: 10,
      margemMinimaPadrao: 20,
    );
    expect(item.margemLucroCadastrada, 0);
    expect(item.precoVendaSugerido, closeTo(12, 0.01));
    expect(item.custoAumentou, isTrue);
  });

  test('custo igual nao destaca aumento', () {
    final item = NfeRevisaoPrecoCalculo.deProduto(
      produto: produto(custo: 8, venda: 12),
      custoNovo: 8,
      margemMinimaPadrao: 20,
    );
    expect(item.custoAumentou, isFalse);
    expect(item.precoVendaSugerido, closeTo(12, 0.01));
  });

  test('custo menor nao destaca aumento e reduz o sugerido', () {
    final item = NfeRevisaoPrecoCalculo.deProduto(
      produto: produto(custo: 10, venda: 15),
      custoNovo: 8,
      margemMinimaPadrao: 20,
    );
    expect(item.custoAumentou, isFalse);
    expect(item.precoVendaSugerido, closeTo(12, 0.01));
  });

  test('upsert por produto fica com o maior custo XML', () {
    final mapa = <int, NfeRevisaoPrecoItem>{};
    NfeRevisaoPrecoCalculo.upsert(
      mapa,
      NfeRevisaoPrecoCalculo.deProduto(
        produto: produto(),
        custoNovo: 11,
        margemMinimaPadrao: 20,
      ),
    );
    NfeRevisaoPrecoCalculo.upsert(
      mapa,
      NfeRevisaoPrecoCalculo.deProduto(
        produto: produto(),
        custoNovo: 13,
        margemMinimaPadrao: 20,
      ),
    );
    expect(mapa, hasLength(1));
    expect(mapa[1]!.custoNovo, 13);
    expect(mapa[1]!.precoVendaSugerido, closeTo(19.5, 0.01));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/produto_busca_util.dart';
import 'package:sistema_vendas/domain/pdv_estoque_semaforo_util.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produto({
  int estoqueReal = 49,
  int estoqueReservado = 0,
  int quantidadeMinima = 1,
}) =>
    Produto(
      id: 1,
      codigoInterno: '004025',
      nome: 'Cimento CP II',
      unidade: 'SC',
      precoCusto: 30,
      precoVenda: 50,
      preco1: 50,
      quantidadeMinima: quantidadeMinima,
      estoqueReal: estoqueReal,
      estoqueReservado: estoqueReservado,
    );

void main() {
  test('dicaBuscaContextual omitida ou contextual', () {
    expect(dicaBuscaContextual(''), isNull);
    expect(dicaBuscaContextual('cimento'), isNull);
    expect(dicaBuscaContextual('ci'), contains('3 caracteres'));
    expect(dicaBuscaContextual('tub%sod%25'), contains('%'));
    expect(dicaBuscaContextual('7891234567890'), contains('barras'));
  });

  test('semaforo usa estoque livre e orcamento como na lista', () {
    final p = _produto(estoqueReal: 10, estoqueReservado: 2, quantidadeMinima: 5);
    expect(p.estoqueLivreParaVenda, 8);
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p),
      PdvEstoqueSemaforoNivel.verde,
    );
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p, quantidadeNoOrcamento: 6),
      PdvEstoqueSemaforoNivel.amarelo,
    );
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p, quantidadeNoOrcamento: 10),
      PdvEstoqueSemaforoNivel.vermelho,
    );
  });
}

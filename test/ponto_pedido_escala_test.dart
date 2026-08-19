import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/ponto_pedido_api_dto.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/services/compras_preditivas_service.dart';

void main() {
  Produto piso({
    int estoqueReal = 144620,
    int quantidadeMinima = 50,
    double media = 2410.33,
    int lead = 7,
    int seguranca = 10,
  }) {
    return Produto(
      id: 1,
      codigoInterno: 'PISO',
      nome: 'Piso',
      unidade: 'M2',
      unidadeCompra: 'CX',
      quantidadePorEmbalagem: 2.63,
      permiteQuantidadeFracionada: true,
      precoCusto: 10,
      precoVenda: 20,
      estoqueReal: estoqueReal,
      quantidadeMinima: quantidadeMinima,
      leadTimeDias: lead,
      estoqueSeguranca: seguranca,
    )..vendaMediaDiaria = media;
  }

  test('PP de cadastro usa media convertida + seguranca em m2', () {
    final p = piso();
    // 2,41033 * 7 + 10 = 26,87
    expect(
      ComprasPreditivasService.pontoPedidoExibicaoDeCadastro(p),
      closeTo(26.872, 0.01),
    );
  });

  test('badge critico compara estoqueExibicao com minimo', () {
    final baixo = piso(estoqueReal: 3000, quantidadeMinima: 50, media: 0);
    expect(baixo.estoqueExibicao, closeTo(3, 0.001));
    expect(baixo.estoqueExibicao <= baixo.quantidadeMinima, isTrue);

    final ok = piso(estoqueReal: 144620, quantidadeMinima: 50, media: 0);
    expect(ok.estoqueExibicao <= ok.quantidadeMinima, isFalse);
    expect(ok.estoqueReal < ok.quantidadeMinima, isFalse);
  });

  test('DTO ponto-pedido ida e volta', () {
    const item = PontoPedidoApiItem(
      produtoId: 9,
      critico: true,
      pontoPedido: 26.87,
      consumo60d: 144620,
      vendaMediaDiariaExibicao: 2.41,
    );
    final deVolta = PontoPedidoApiItem.fromApiMap(item.toApiMap());
    expect(deVolta, isNotNull);
    expect(deVolta!.produtoId, 9);
    expect(deVolta.critico, isTrue);
    expect(deVolta.pontoPedido, closeTo(26.87, 0.001));
    expect(deVolta.consumo60d, 144620);
    expect(deVolta.vendaMediaDiariaExibicao, closeTo(2.41, 0.001));
  });
}

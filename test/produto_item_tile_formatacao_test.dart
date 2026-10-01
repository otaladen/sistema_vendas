import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_consulta_detalhe_linha.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  test('subtitulo da lista PDV traz SKU e EAN sem fator de embalagem', () {
    final produto = Produto(
      codigoInterno: '008858',
      nome: 'Refrigerante',
      codigoBarras: '7891000100103',
      unidade: 'UN',
      unidadeCompra: 'UN',
      quantidadePorEmbalagem: 12,
      embalagemMultiplica: true,
      precoCusto: 1,
      precoVenda: 2,
      preco1: 2,
      quantidadeMinima: 0,
    );

    final rotuloEmbalagem = produto.rotuloConversaoEmbalagem;
    expect(rotuloEmbalagem, isNotEmpty);
    expect(rotuloEmbalagem, contains('Fator'));
    expect(rotuloEmbalagem, contains('por embalagem'));

    final subtitulo = PdvConsultaDetalheLinhaUtil.montar(produto);

    expect(subtitulo, contains('SKU 008858'));
    expect(subtitulo, contains('EAN 7891000100103'));
    expect(subtitulo, isNot(contains('Fator')));
    expect(subtitulo, isNot(contains('por embalagem')));
    expect(subtitulo, isNot(contains(rotuloEmbalagem)));
  });
}

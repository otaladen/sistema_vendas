import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/quantidade_venda_util.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
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

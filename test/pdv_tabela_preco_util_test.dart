import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_tabela_preco_util.dart';

void main() {
  test('proxima cicla preco1 -> preco2 -> preco3 -> preco1', () {
    expect(PdvTabelaPrecoUtil.proxima('preco1'), 'preco2');
    expect(PdvTabelaPrecoUtil.proxima('preco2'), 'preco3');
    expect(PdvTabelaPrecoUtil.proxima('preco3'), 'preco1');
  });

  test('carrinhoMisto detecta tabelas diferentes', () {
    expect(
      PdvTabelaPrecoUtil.carrinhoMisto(['preco1', 'preco2']),
      isTrue,
    );
    expect(
      PdvTabelaPrecoUtil.carrinhoMisto(['preco2', 'preco2']),
      isFalse,
    );
  });

  test('meiosPagamentoUniao junta opcoes das tabelas', () {
    final mapa = {
      'preco1': ['fiado', 'cartao_credito'],
      'preco2': ['pix', 'dinheiro'],
      'preco3': ['dinheiro'],
    };
    final ordem = [
      'dinheiro',
      'pix',
      'cartao_credito',
      'fiado',
    ];
    expect(
      PdvTabelaPrecoUtil.meiosPagamentoUniao(
        ['preco1', 'preco2'],
        mapa,
        ordem,
      ),
      ['dinheiro', 'pix', 'cartao_credito', 'fiado'],
    );
  });
}

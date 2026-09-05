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

  test('rotulos usam Preco 1 / Preco 2 / Preco 3', () {
    expect(PdvTabelaPrecoUtil.rotulo('preco1'), 'Preco 1');
    expect(PdvTabelaPrecoUtil.rotulo('preco2'), 'Preco 2');
    expect(PdvTabelaPrecoUtil.rotulo('preco3'), 'Preco 3');
    expect(PdvTabelaPrecoUtil.rotuloCurto('preco1'), 'P1');
    expect(PdvTabelaPrecoUtil.rotuloCurto('preco2'), 'P2');
    expect(PdvTabelaPrecoUtil.rotuloCurto('preco3'), 'P3');
  });
}

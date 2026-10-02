import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/produto_unidades_catalogo.dart';

void main() {
  test('catalogo inclui M3 e unidades novas de material de construcao', () {
    expect(ProdutoUnidadesCatalogo.unidadesVenda, contains('M3'));
    expect(ProdutoUnidadesCatalogo.unidadesVenda, containsAll(<String>[
      'FD',
      'RL',
      'PCT',
      'PAR',
      'DZ',
      'TON',
      'ML',
      'G',
    ]));
    expect(
      ProdutoUnidadesCatalogo.unidadesInternasValidas,
      ProdutoUnidadesCatalogo.unidadesVenda,
    );
  });

  test('normalizarUnidadeVenda mapeia alias comuns', () {
    expect(ProdutoUnidadesCatalogo.normalizarUnidadeVenda('mt'), 'M');
    expect(ProdutoUnidadesCatalogo.normalizarUnidadeVenda('METRO'), 'M');
    expect(ProdutoUnidadesCatalogo.normalizarUnidadeVenda(' m3 '), 'M3');
    expect(ProdutoUnidadesCatalogo.normalizarUnidadeVenda('PACOTE'), 'PCT');
    expect(ProdutoUnidadesCatalogo.normalizarUnidadeVenda('duzia'), 'DZ');
  });
}

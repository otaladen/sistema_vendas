import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/produto_repository.dart';

void main() {
  test('mensagem de SKU duplicado', () {
    final e = ProdutoSkuDuplicadoException(
      sku: '8858',
      produtoExistenteNome: 'Piso Arielle',
      produtoExistenteId: 12,
    );
    expect(
      e.toString(),
      'SKU "8858" ja cadastrado no produto "Piso Arielle".',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fornecedor_entrada_nfe_indice.dart';

void main() {
  test('lista fornecedores distintos das NF-e e produtos vinculados', () {
    final indice = FornecedorEntradaNfeIndice.deLancamentos([
      FornecedorEntradaNfeLancamento(
        produtoId: 1,
        nomeFornecedor: 'Votorantim',
        data: DateTime.utc(2026, 1, 10),
      ),
      FornecedorEntradaNfeLancamento(
        produtoId: 1,
        nomeFornecedor: 'Tigre Dist',
        data: DateTime.utc(2026, 3, 1),
      ),
      FornecedorEntradaNfeLancamento(
        produtoId: 2,
        nomeFornecedor: 'votorantim',
        data: DateTime.utc(2026, 2, 1),
      ),
    ]);

    expect(indice.nomesOrdenados, ['Tigre Dist', 'Votorantim']);
    expect(indice.produtoIdsDe('Votorantim'), {1, 2});
    expect(indice.produtoDoFornecedor(1, 'tigre dist'), isTrue);
    expect(indice.ultimoFornecedorDe(1), 'Tigre Dist');
    expect(indice.fornecedoresDoProduto(1), ['Tigre Dist', 'Votorantim']);
  });

  test('fornecedor desconhecido nao casa produto', () {
    final indice = FornecedorEntradaNfeIndice.deLancamentos(const []);
    expect(indice.produtoDoFornecedor(9, 'X'), isFalse);
  });

  test('toApiMap/deApiMap preserva produtos por fornecedor', () {
    final origem = FornecedorEntradaNfeIndice.deLancamentos([
      FornecedorEntradaNfeLancamento(
        produtoId: 10,
        nomeFornecedor: 'Acme',
        data: DateTime.utc(2026, 4, 1),
      ),
      FornecedorEntradaNfeLancamento(
        produtoId: 20,
        nomeFornecedor: 'Acme',
        data: DateTime.utc(2026, 5, 1),
      ),
    ]);
    final volta = FornecedorEntradaNfeIndice.deApiMap(origem.toApiMap());
    expect(volta.nomesOrdenados, ['Acme']);
    expect(volta.produtoIdsDe('acme'), {10, 20});
  });
}

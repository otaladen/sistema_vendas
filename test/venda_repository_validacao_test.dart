import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/venda_repository.dart';

void main() {
  group('validarItemVendaInput', () {
    ItemVendaInput base({
      int produtoId = 1,
      int quantidade = 2,
      double precoUnitario = 10,
    }) =>
        ItemVendaInput(
          produtoId: produtoId,
          quantidade: quantidade,
          precoUnitario: precoUnitario,
        );

    test('aceita item valido', () {
      expect(() => validarItemVendaInput(base()), returnsNormally);
    });

    test('rejeita produto invalido', () {
      expect(
        () => validarItemVendaInput(base(produtoId: 0)),
        throwsArgumentError,
      );
    });

    test('rejeita quantidade zero', () {
      expect(
        () => validarItemVendaInput(base(quantidade: 0)),
        throwsArgumentError,
      );
    });

    test('rejeita preco negativo', () {
      expect(
        () => validarItemVendaInput(base(precoUnitario: -1)),
        throwsArgumentError,
      );
    });
  });
}

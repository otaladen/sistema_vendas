import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/troca_com_nota_pdv_intent.dart';

void main() {
  group('creditoDevolucaoAplicavelNoSubtotalPdv', () {
    test('usa credito inteiro quando cabe no subtotal', () {
      expect(
        creditoDevolucaoAplicavelNoSubtotalPdv(
          creditoDevolucaoReais: 9.90,
          subtotalElegivelDesconto: 18.90,
        ),
        9.90,
      );
    });

    test('limita ao subtotal quando credito e maior', () {
      expect(
        creditoDevolucaoAplicavelNoSubtotalPdv(
          creditoDevolucaoReais: 50,
          subtotalElegivelDesconto: 18.90,
        ),
        18.90,
      );
    });

    test('zero sem itens no carrinho', () {
      expect(
        creditoDevolucaoAplicavelNoSubtotalPdv(
          creditoDevolucaoReais: 9.90,
          subtotalElegivelDesconto: 0,
        ),
        0,
      );
    });
  });
}

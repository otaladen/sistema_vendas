import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/cancelada_por_rotulo.dart';

void main() {
  test('login de operador permanece igual', () {
    expect(CanceladaPorRotulo.exibicao('admin'), 'admin');
  });

  test('slug da ferramenta de limpeza nao vaza na UI', () {
    expect(
      CanceladaPorRotulo.exibicao('ferramenta_limpar_entregas'),
      'Sistema (limpeza de entregas)',
    );
  });

  test('vazio vira nao informado', () {
    expect(CanceladaPorRotulo.exibicao('  '), 'Nao informado');
  });
}

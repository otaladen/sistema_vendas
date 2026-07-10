import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/custo_medio_entrada_util.dart';

void main() {
  test('custo medio pondera saldo anterior com entrada da nota', () {
    final cm = CustoMedioEntradaUtil.custoMedioAposEntrada(
      estoqueAntes: 49,
      custoMedioAntes: 45,
      quantidadeEntrada: 100,
      custoUnitarioEntrada: 32.5,
    );
    expect(cm, closeTo(36.61, 0.01));
  });

  test('custo medio sem saldo anterior usa custo da nota', () {
    final cm = CustoMedioEntradaUtil.custoMedioAposEntrada(
      estoqueAntes: 0,
      custoMedioAntes: 0,
      quantidadeEntrada: 100,
      custoUnitarioEntrada: 32.5,
    );
    expect(cm, 32.5);
  });

  test('estorno reverte media ponderada da entrada', () {
    const estoqueApos = 49;
    const qtdEstornada = 100;
    const cmAtual = 36.61073825503356;
    const custoEntrada = 32.5;
    final cmAntes = CustoMedioEntradaUtil.custoMedioAntesEntrada(
      estoqueAposEstorno: estoqueApos,
      quantidadeEntradaEstornada: qtdEstornada,
      custoMedioAtual: cmAtual,
      custoUnitarioEntrada: custoEntrada,
    );
    expect(cmAntes, closeTo(45, 0.01));
  });
}

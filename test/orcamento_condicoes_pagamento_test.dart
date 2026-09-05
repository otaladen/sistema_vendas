import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/orcamento_condicoes_pagamento.dart';

void main() {
  String moeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  test('linhas inclui a vista e parcelas 2x ate o teto do PDV', () {
    final linhas = OrcamentoCondicoesPagamento.linhas(
      total: 100,
      formatarMoeda: moeda,
    );
    expect(linhas.first, 'A vista (Dinheiro/PIX/Debito): R\$ 100.00');
    expect(linhas, contains('Cartao credito:'));
    expect(linhas, contains('  2x de R\$ 50.00'));
    expect(linhas, contains('  3x de R\$ 33.33'));
    expect(linhas, contains('  12x de R\$ 8.33'));
    expect(linhas.any((l) => l.contains(' 1x') || l.startsWith('1x')), isFalse);
    expect(
      linhas.length,
      OrcamentoCondicoesPagamento.quantidadeLinhasLayout() - 2,
    );
  });

  test('total invalido vira zero na simulacao', () {
    final linhas = OrcamentoCondicoesPagamento.linhas(
      total: double.nan,
      formatarMoeda: moeda,
    );
    expect(linhas.first, contains('R\$ 0.00'));
  });
}

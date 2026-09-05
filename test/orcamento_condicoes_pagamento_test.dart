import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/orcamento_condicoes_pagamento.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  String moeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  test('dinheiro/pix/debito imprimem so a vista, sem lista de parcelas', () {
    for (final meio in [
      PagamentoMeio.dinheiro,
      PagamentoMeio.pix,
      PagamentoMeio.cartaoDebito,
    ]) {
      final linhas = OrcamentoCondicoesPagamento.linhas(
        total: 100,
        formatarMoeda: moeda,
        formaPagamento: meio,
      );
      expect(linhas, hasLength(1));
      expect(
        linhas.single,
        'Forma de Pagamento: A vista (Dinheiro/PIX/Debito) - Total: R\$ 100.00',
      );
      expect(linhas.single.contains('2x'), isFalse);
      expect(linhas.single.contains('12x'), isFalse);
    }
  });

  test('cartao de credito imprime so as parcelas escolhidas', () {
    final linhas = OrcamentoCondicoesPagamento.linhas(
      total: 90,
      formatarMoeda: moeda,
      formaPagamento: PagamentoMeio.cartaoCredito,
      quantidadeParcelas: 3,
    );
    expect(linhas, hasLength(1));
    expect(
      linhas.single,
      'Forma de Pagamento: Cartao de credito - 3x de R\$ 30.00',
    );
    expect(linhas.any((l) => l.contains('2x') || l.contains('12x')), isFalse);
  });

  test('misto imprime cada meio escolhido, sem tabela generica', () {
    final json = PagamentoOrcamentoCodec.encode(const [
      PagamentoOrcamentoLinha(meio: PagamentoMeio.pix, valor: 40),
      PagamentoOrcamentoLinha(
        meio: PagamentoMeio.cartaoCredito,
        valor: 60,
        parcelas: 2,
      ),
    ]);
    final linhas = OrcamentoCondicoesPagamento.linhasDaVenda(
      Venda(formaPagamento: PagamentoMeio.misto, pagamentosJson: json),
      total: 100,
      formatarMoeda: moeda,
    );
    expect(linhas, hasLength(2));
    expect(
      linhas[0],
      'Forma de Pagamento: A vista (Dinheiro/PIX/Debito) - Total: R\$ 40.00',
    );
    expect(
      linhas[1],
      'Forma de Pagamento: Cartao de credito - 2x de R\$ 30.00',
    );
    expect(linhas.any((l) => l.contains('12x')), isFalse);
  });

  test('total invalido vira zero na condicao a vista', () {
    final linhas = OrcamentoCondicoesPagamento.linhas(
      total: double.nan,
      formatarMoeda: moeda,
      formaPagamento: PagamentoMeio.dinheiro,
    );
    expect(linhas.single, contains('R\$ 0.00'));
  });
}

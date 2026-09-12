import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/orcamento_condicoes_pagamento.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  String moeda(double v) => 'R\$ ${v.toStringAsFixed(2)}';

  test('dinheiro/pix/debito imprimem o meio escolhido, sem lista de parcelas', () {
    expect(
      OrcamentoCondicoesPagamento.linhas(
        total: 100,
        formatarMoeda: moeda,
        formaPagamento: PagamentoMeio.dinheiro,
      ).single,
      'Dinheiro a vista - Total: R\$ 100.00',
    );
    expect(
      OrcamentoCondicoesPagamento.linhas(
        total: 100,
        formatarMoeda: moeda,
        formaPagamento: PagamentoMeio.pix,
      ).single,
      'PIX a vista - Total: R\$ 100.00',
    );
    expect(
      OrcamentoCondicoesPagamento.linhas(
        total: 100,
        formatarMoeda: moeda,
        formaPagamento: PagamentoMeio.cartaoDebito,
      ).single,
      'Cartao de debito a vista - Total: R\$ 100.00',
    );
  });

  test('cartao de credito imprime so as parcelas escolhidas', () {
    final linhas = OrcamentoCondicoesPagamento.linhas(
      total: 90,
      formatarMoeda: moeda,
      formaPagamento: PagamentoMeio.cartaoCredito,
      quantidadeParcelas: 3,
    );
    expect(linhas, hasLength(1));
    expect(linhas.single, 'Cartao de credito 3x de R\$ 30.00');
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
    expect(linhas[0], 'PIX a vista - Total: R\$ 40.00');
    expect(linhas[1], 'Cartao de credito 2x de R\$ 30.00');
    expect(linhas.any((l) => l.contains('12x')), isFalse);
  });

  test('resumo financeiro destaca a forma sugerida no checkout', () {
    final texto = OrcamentoCondicoesPagamento.resumoFinanceiroDaVenda(
      Venda(
        formaPagamento: PagamentoMeio.cartaoCredito,
        quantidadeParcelas: 3,
        total: 150,
      ),
      total: 150,
      formatarMoeda: moeda,
    );
    expect(texto, 'Pagamento: Cartao de credito 3x de R\$ 50.00');
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

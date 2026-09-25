import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/domain/pagamentos_recebidos_caixa.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/cupom_nao_fiscal_venda_pdf.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  final service = FocusNfeService(
    config: FocusNfeConfig.homologacao(
      apiToken: 'token-teste',
      cnpjEmitente: '32662298000191',
      inscricaoEstadualEmitente: '123456789',
    ),
  );

  ItemVenda item(String codigo, String nome, double preco) => ItemVenda(
        nomeProduto: nome,
        quantidade: 1000,
        escalaQuantidade: ItemVenda.escalaQuantidadeMilesimos,
        precoUnitario: preco,
        precoCustoUnitario: 1,
      )..produto.target = Produto(
          codigoInterno: codigo,
          nome: nome,
          ncm: '87089990',
          quantidadeMinima: 1,
          precoCusto: 1,
          precoVenda: preco,
        );

  /// Controle #1744: orcamento previa R$ 50 em dinheiro; cliente entregou
  /// R$ 60 no caixa. O caixa grava as linhas somando o total da venda e o
  /// excesso em valorRecebidoCaixa/valorTrocoCaixa.
  Venda vendaOrcamentoComTroco() => Venda(
        id: 1744,
        formaPagamento: 'misto',
        pagamentosJson: PagamentoOrcamentoCodec.encode([
          const PagamentoOrcamentoLinha(
            meio: 'cartao_credito',
            valor: 150,
            parcelas: 2,
          ),
          const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 50),
        ]),
        valorRecebidoCaixa: 210,
        valorTrocoCaixa: 10,
      )
        ..total = 200
        ..itens.addAll([
          item('928', 'Assento Durin Especial', 185),
          item('1828', 'Desengripante White LUB 300ml', 15.5),
        ]);

  Map<String, String> valorPorForma(List formas) => {
        for (final f in formas.cast<Map>())
          f['forma_pagamento'] as String: f['valor_pagamento'] as String,
      };

  test(
      'orcamento com R\$ 50 em dinheiro pago com R\$ 60 no caixa envia '
      'R\$ 60 em dinheiro e R\$ 10 de valor_troco a Focus', () {
    final payload = service.montarPayloadNfce(vendaOrcamentoComTroco());

    expect(payload['valor_total'], '200.00');
    expect(payload['valor_troco'], '10.00');

    final formas = payload['formas_pagamento'] as List;
    expect(formas.length, 2);
    final porForma = valorPorForma(formas);
    expect(porForma['03'], '150.00');
    expect(porForma['01'], '60.00');

    final somaPago = formas.fold<double>(
      0,
      (s, f) => s + double.parse((f as Map)['valor_pagamento'] as String),
    );
    expect(somaPago, 210.0);
    expect(
      somaPago - double.parse(payload['valor_troco'] as String),
      double.parse(payload['valor_total'] as String),
    );
  });

  test('cupom impresso mostra os mesmos pagamentos enviados a Focus', () {
    final venda = vendaOrcamentoComTroco();
    final payload = service.montarPayloadNfce(venda);
    final focus = (payload['formas_pagamento'] as List)
        .map((f) => double.parse((f as Map)['valor_pagamento'] as String))
        .toList();

    final cupom = CupomNaoFiscalVendaPdf.linhasPagamentoCupom(
      venda,
      totalRecebido: venda.valorRecebidoCaixa,
      troco: venda.valorTrocoCaixa,
    ).map((l) => l.valor).toList();

    expect(cupom, focus);
    expect(cupom, [150.0, 60.0]);
  });

  test('linhas ja com o valor entregue nao somam o troco duas vezes', () {
    final venda = Venda(
      formaPagamento: 'misto',
      pagamentosJson: PagamentoOrcamentoCodec.encode([
        const PagamentoOrcamentoLinha(meio: 'cartao_credito', valor: 150),
        const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 60),
      ]),
      valorTrocoCaixa: 10,
    )..total = 200;

    final linhas = PagamentosRecebidosCaixa.linhasMisto(venda);
    expect(linhas.map((l) => l.valor), [150.0, 60.0]);
  });

  test('misto sem troco mantem as linhas gravadas', () {
    final venda = Venda(
      formaPagamento: 'misto',
      pagamentosJson: PagamentoOrcamentoCodec.encode([
        const PagamentoOrcamentoLinha(meio: 'pix', valor: 120),
        const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 80),
      ]),
    )..total = 200;

    final payload = service.montarPayloadNfce(
      venda..itens.add(item('1', 'Produto', 200)),
    );
    expect(payload.containsKey('valor_troco'), isFalse);
    expect(valorPorForma(payload['formas_pagamento'] as List), {
      '17': '120.00',
      '01': '80.00',
    });
  });
}

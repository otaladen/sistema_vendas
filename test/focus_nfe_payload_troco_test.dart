import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  final config = FocusNfeConfig.homologacao(
    apiToken: 'token-teste',
    cnpjEmitente: '32662298000191',
    inscricaoEstadualEmitente: '123456789',
  );
  final service = FocusNfeService(config: config);

  Venda vendaMistaComTroco({required double total}) {
    final produto = Produto(
      codigoInterno: 'P1',
      nome: 'Produto',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 10,
      precoVenda: total,
    );
    final item = ItemVenda(
      nomeProduto: 'Produto',
      quantidade: 1,
      precoUnitario: total,
      precoCustoUnitario: 10,
    )..produto.target = produto;

    return Venda(
      id: 19,
      formaPagamento: 'misto',
      pagamentosJson: PagamentoOrcamentoCodec.encode([
        const PagamentoOrcamentoLinha(meio: 'pix', valor: 40),
        const PagamentoOrcamentoLinha(meio: 'dinheiro', valor: 70),
      ]),
    )..itens.add(item);
  }

  test('NFC-e mista com pagamento acima do total inclui valor_troco', () {
    final venda = vendaMistaComTroco(total: 100);
    final payload = service.montarPayloadNfce(venda);

    expect(payload['valor_total'], '100.00');
    expect(payload['valor_troco'], '10.00');
    final formas = payload['formas_pagamento'] as List;
    expect(formas.length, 2);
    final soma = formas.fold<double>(
      0,
      (s, f) => s + double.parse((f as Map)['valor_pagamento'] as String),
    );
    expect(soma, 110.0);
  });

  test('NFC-e sem excedente de pagamento nao envia valor_troco', () {
    final venda = Venda(
      id: 20,
      formaPagamento: 'pix',
    );
    final produto = Produto(
      codigoInterno: 'P2',
      nome: 'Produto',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 10,
      precoVenda: 50,
    );
    venda.itens.add(
      ItemVenda(
        nomeProduto: 'Produto',
        quantidade: 1,
        precoUnitario: 50,
        precoCustoUnitario: 10,
      )..produto.target = produto,
    );

    final payload = service.montarPayloadNfce(venda);
    expect(payload.containsKey('valor_troco'), isFalse);
  });
}

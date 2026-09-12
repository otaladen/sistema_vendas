import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pagamento_orcamento.dart';
import 'package:sistema_vendas/model/cliente.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_payload_builder.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  final config = FocusNfeConfig.homologacao(
    apiToken: 'token-teste',
    cnpjEmitente: '32662298000191',
    inscricaoEstadualEmitente: '123456789',
  );
  final service = FocusNfeService(config: config);

  double somaFormas(List formas) => formas.fold<double>(
        0,
        (s, f) =>
            s +
            double.parse((f as Map)['valor_pagamento'] as String),
      );

  test('pagamento misto com frete reconcilia vPag ao valor_total da nota', () {
    final item = ItemVenda(
      nomeProduto: 'Tijolo',
      quantidade: 10,
      precoUnitario: 5,
      precoCustoUnitario: 1,
    )..produto.target = Produto(
        codigoInterno: '1',
        nome: 'Tijolo',
        ncm: '69041000',
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 5,
      );

    final venda = Venda(
      id: 301,
      formaPagamento: 'misto',
      pagamentosJson: PagamentoOrcamentoCodec.encode([
        const PagamentoOrcamentoLinha(meio: 'pix', valor: 30),
        const PagamentoOrcamentoLinha(meio: 'cartao_debito', valor: 20),
      ]),
    )
      ..valorFrete = 15
      ..total = 65
      ..itens.add(item);

    final payload = service.montarPayloadNfce(venda);
    expect(payload['valor_total'], '65.00');
    final formas = payload['formas_pagamento'] as List;
    expect(somaFormas(formas), 65.0);
    expect(payload.containsKey('valor_troco'), isFalse);
  });

  test('dinheiro com valor recebido maior gera valor_troco', () {
    final item = ItemVenda(
      nomeProduto: 'Produto',
      quantidade: 1,
      precoUnitario: 100,
      precoCustoUnitario: 10,
    )..produto.target = Produto(
        codigoInterno: 'P1',
        nome: 'Produto',
        ncm: '25232910',
        quantidadeMinima: 1,
        precoCusto: 10,
        precoVenda: 100,
      );

    final venda = Venda(
      id: 302,
      formaPagamento: 'dinheiro',
      valorRecebidoCaixa: 150,
      valorTrocoCaixa: 50,
    )..itens.add(item);

    final payload = service.montarPayloadNfce(venda);
    expect(payload['valor_total'], '100.00');
    expect(payload['valor_troco'], '50.00');
    final formas = payload['formas_pagamento'] as List;
    expect(formas.length, 1);
    expect((formas.first as Map)['valor_pagamento'], '150.00');
    expect(somaFormas(formas), 150.0);
  });

  test('validarReconciliarPagamentosNoPayload corrige payload inconsistente', () {
    final payload = <String, dynamic>{
      'valor_total': '28.00',
      'formas_pagamento': [
        {'forma_pagamento': '17', 'valor_pagamento': '15.00'},
        {'forma_pagamento': '04', 'valor_pagamento': '12.50'},
      ],
    };
    FocusNfePayloadBuilder.validarReconciliarPagamentosNoPayload(payload);
    expect(somaFormas(payload['formas_pagamento'] as List), 28.0);
  });

  test('NFC-e entrega com frete e pagamento unico cobre valor_total', () {
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 50,
      precoCustoUnitario: 20,
    )..produto.target = Produto(
        codigoInterno: '2',
        nome: 'Cimento',
        ncm: '69041000',
        quantidadeMinima: 1,
        precoCusto: 20,
        precoVenda: 50,
      );

    final venda = Venda(
      id: 303,
      formaPagamento: 'pix',
    )
      ..valorFrete = 15
      ..total = 65
      ..itens.add(item);

    final endereco = EnderecoCliente(
      tipo: 'entrega',
      padraoCarreto: true,
      cep: '44001-000',
      endereco: 'Rua A',
      numero: '1',
      bairro: 'Centro',
      cidade: 'Feira de Santana',
      uf: 'BA',
      codigoIbge: '2910800',
    );
    final cliente = Cliente(nomeRazao: 'Maria', documento: '52998224725')
      ..definirEnderecos([endereco]);

    final payload = service.montarPayloadNfce(
      venda,
      cliente: cliente,
      entregaDomicilio: true,
      enderecoEntrega: endereco,
      codigoMunicipioIbge: '2910800',
    );
    expect(payload['valor_total'], '65.00');
    expect(
      somaFormas(payload['formas_pagamento'] as List),
      double.parse(payload['valor_total'] as String),
    );
  });
}

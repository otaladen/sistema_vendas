import 'package:flutter_test/flutter_test.dart';
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

  Produto produto(String codigo, String nome) => Produto(
        codigoInterno: codigo,
        nome: nome,
        ncm: '39174090',
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 10,
      );

  test(
    'NFC-e com desconto no total rateia valor_desconto nos itens (rejeicao 537)',
    () {
      // Cupom real: 14,90 + 1,40 = 16,30; desconto 0,40; TOTAL 15,90.
      final item1 = ItemVenda(
        nomeProduto: 'Obturador Olifix',
        quantidade: 1,
        precoUnitario: 14.90,
        precoCustoUnitario: 1,
      )..produto.target = produto('2081', 'Obturador');
      final item2 = ItemVenda(
        nomeProduto: 'Bucha RED PVC',
        quantidade: 2,
        precoUnitario: 0.70,
        precoCustoUnitario: 0.1,
      )..produto.target = produto('42', 'Bucha');

      final venda = Venda()
        ..id = 2108
        ..total = 15.90
        ..itens.add(item1)
        ..itens.add(item2);

      expect(venda.somaSubtotalItens, closeTo(16.30, 0.001));
      expect(venda.descontoImplicitoTotal, closeTo(0.40, 0.001));

      final payload = service.montarPayloadNfce(venda);
      final items = (payload['items'] as List).cast<Map<String, dynamic>>();

      expect(payload['valor_produtos'], '16.30');
      expect(payload['valor_desconto'], '0.40');
      expect(payload['valor_total'], '15.90');

      var somaDescItens = 0.0;
      for (final it in items) {
        final d = double.tryParse(it['valor_desconto']?.toString() ?? '') ?? 0;
        somaDescItens += d;
        expect(d, greaterThan(0));
        final bruto =
            double.tryParse(it['valor_bruto']?.toString() ?? '') ?? 0;
        final baseIbs =
            (it['ibs_cbs_base_calculo'] as num?)?.toDouble() ?? bruto;
        expect(baseIbs, closeTo(bruto - d, 0.001));
      }
      expect(somaDescItens, closeTo(0.40, 0.001));
      expect(
        somaDescItens,
        closeTo(double.parse(payload['valor_desconto'] as String), 0.001),
      );
    },
  );

  test('NFC-e sem desconto nao envia valor_desconto nos itens', () {
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 35,
      precoCustoUnitario: 20,
    )..produto.target = produto('CIM', 'Cimento');

    final venda = Venda()
      ..id = 1
      ..total = 35
      ..itens.add(item);

    final payload = service.montarPayloadNfce(venda);
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;
    expect(payload['valor_desconto'], '0.00');
    expect(itemPayload.containsKey('valor_desconto'), isFalse);
  });
}

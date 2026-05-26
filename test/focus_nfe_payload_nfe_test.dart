import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

FocusNfeDestinatarioNfe destinatario({
  String doc = '12345678000199',
  String uf = 'BA',
  String indicadorIe = '1',
  String ie = '123456789',
}) =>
    FocusNfeDestinatarioNfe(
      nome: 'Construtora Teste',
      documento: doc,
      inscricaoEstadual: ie,
      indicadorInscricaoEstadual: indicadorIe,
      logradouro: 'Rua A',
      numero: '100',
      bairro: 'Centro',
      municipio: 'Salvador',
      codigoMunicipioIbge: '2927408',
      uf: uf,
      cep: '40000000',
    );

void main() {
  final config = FocusNfeConfig.homologacao(
    apiToken: 'token-teste',
    cnpjEmitente: '32662298000191',
    inscricaoEstadualEmitente: '123456789',
  );
  final service = FocusNfeService(config: config);

  test('NF-e BA contribuinte usa CFOP 5101 e consumidor_final 0', () {
    final produto = Produto(
      codigoInterno: 'CIM',
      nome: 'Cimento',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 10,
      precoVenda: 20,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 1,
      precoUnitario: 20,
      precoCustoUnitario: 10,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 10
      ..itens.add(item);

    final payload = service.montarPayloadNfe(
      venda,
      destinatario: destinatario(),
    );

    expect(payload['consumidor_final'], '0');
    expect(payload['uf_destinatario'], 'BA');
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;
    expect(itemPayload['cfop'], FiscalConfig.cfopEstadualContribuinteTributado);
    expect(itemPayload['codigo_barras_comercial'], 'SEM GTIN');
  });

  test('NF-e interestadual ST usa CFOP 6403', () {
    final produto = Produto(
      codigoInterno: 'TEL',
      nome: 'Telha',
      ncm: '69041000',
      grupoTributario: 'substituicao_tributaria',
      cest: '1000300',
      codigoBarras: '7891234567890',
      quantidadeMinima: 1,
      precoCusto: 5,
      precoVenda: 10,
    );
    final item = ItemVenda(
      nomeProduto: 'Telha',
      quantidade: 2,
      precoUnitario: 10,
      precoCustoUnitario: 5,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 11
      ..itens.add(item);

    final payload = service.montarPayloadNfe(
      venda,
      destinatario: destinatario(uf: 'SP'),
    );

    expect(payload['local_destino'], '2');
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;
    expect(itemPayload['cfop'], FiscalConfig.cfopInterestadualSt);
    expect(itemPayload['codigo_barras_comercial'], '7891234567890');
    expect(itemPayload['cest'], '1000300');
  });

  test('rejeita contribuinte sem IE', () {
    expect(
      () => destinatario(ie: '').validar(),
      throwsA(
        isA<FocusNfeValidacaoException>().having(
          (e) => e.message,
          'message',
          contains('Inscricao Estadual obrigatoria'),
        ),
      ),
    );
  });

  test('fiado monta fatura e duplicatas', () {
    final produto = Produto(
      codigoInterno: 'A',
      nome: 'A',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 1,
      precoVenda: 100,
    );
    final item = ItemVenda(
      nomeProduto: 'A',
      quantidade: 1,
      precoUnitario: 100,
      precoCustoUnitario: 1,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 12
      ..numeroOrcamento = 500
      ..formaPagamento = 'fiado'
      ..total = 100
      ..planoFiadoJson =
          '[{"numero":1,"valor":50,"vencimento":"2026-06-01T00:00:00.000Z"},'
          '{"numero":2,"valor":50,"vencimento":"2026-07-01T00:00:00.000Z"}]'
      ..itens.add(item);

    final payload = service.montarPayloadNfe(
      venda,
      destinatario: destinatario(),
    );

    expect(payload['numero_fatura'], '500');
    expect(payload['valor_liquido_fatura'], '100.00');
    final dups = payload['duplicatas'] as List;
    expect(dups.length, 2);
    expect(dups.first['numero'], '001');
    expect(dups.first['data_vencimento'], isNotEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/item_venda.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  test('montarPayloadNfce inclui emitente, natureza e tipo_emissao normal', () {
    final config = FocusNfeConfig.homologacao(
      apiToken: 'token-teste',
      cnpjEmitente: '32662298000191',
      inscricaoEstadualEmitente: '123456789',
      regimeTributarioEmitente: 3,
    );
    final service = FocusNfeService(config: config);

    final produto = Produto(
      codigoInterno: 'CIM-01',
      nome: 'Cimento',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 20,
      precoVenda: 35,
    );
    final item = ItemVenda(
      nomeProduto: 'Cimento',
      quantidade: 2,
      precoUnitario: 35.0,
      precoCustoUnitario: 20,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 42
      ..itens.add(item);

    final payload = service.montarPayloadNfce(venda);

    expect(payload['cnpj_emitente'], '32662298000191');
    expect(payload['inscricao_estadual_emitente'], '123456789');
    expect(payload['regime_tributario_emitente'], '3');
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;
    expect(itemPayload['icms_origem'], '0');
    expect(itemPayload['icms_situacao_tributaria'], '00');
    expect(itemPayload['pis_situacao_tributaria'], '01');
    expect(itemPayload['cofins_situacao_tributaria'], '01');
    expect(itemPayload.containsKey('cest'), isFalse);
    expect(itemPayload['codigo_barras_comercial'], 'SEM GTIN');
    expect(payload['uf_emitente'], 'BA');
    expect(payload['natureza_operacao'], 'Venda de mercadoria');
    expect(payload['tipo_emissao'], '1');
    expect(payload.containsKey('forma_emissao'), isFalse);
  });

  test('referencia NFC-e e NF-e usam venda_{id} estavel', () {
    final venda = Venda()..id = 99;
    expect(FocusNfeService.referenciaVendaNfce(venda), 'venda_99');
    expect(FocusNfeService.referenciaVendaNfe(venda), 'venda_99_nfe');
  });

  test('montarPayloadNfce contingencia inclui forma_emissao offline no corpo', () {
    final config = FocusNfeConfig.homologacao(
      apiToken: 'token-teste',
      cnpjEmitente: '32662298000191',
      inscricaoEstadualEmitente: '123456789',
    );
    final service = FocusNfeService(config: config);

    final produto = Produto(
      codigoInterno: 'T1',
      nome: 'Tijolo',
      ncm: '69041000',
      quantidadeMinima: 1,
      precoCusto: 0.5,
      precoVenda: 1,
    );
    final item = ItemVenda(
      nomeProduto: 'Tijolo',
      quantidade: 1,
      precoUnitario: 1.0,
      precoCustoUnitario: 0.5,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 1
      ..itens.add(item);

    final payload = service.montarPayloadNfce(
      venda,
      tipoEmissao: FocusNfeEmissaoSefaz.tipoEmissaoContingenciaOfflineNfce,
      formaEmissao: FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce,
    );

    expect(payload['tipo_emissao'], '9');
    expect(payload['forma_emissao'], 'offline');
  });

  test('item ST envia CEST e CST 60; origem e PIS customizados no produto', () {
    final config = FocusNfeConfig.homologacao(
      apiToken: 'token-teste',
      cnpjEmitente: '32662298000191',
      inscricaoEstadualEmitente: '123456789',
    );
    final service = FocusNfeService(config: config);

    final produto = Produto(
      codigoInterno: 'TELHA',
      nome: 'Telha',
      ncm: '69041000',
      cest: '1000300',
      grupoTributario: 'substituicao_tributaria',
      icmsOrigem: '1',
      pisCofinsSituacaoTributaria: '06',
      quantidadeMinima: 1,
      precoCusto: 5,
      precoVenda: 10,
    );
    final item = ItemVenda(
      nomeProduto: 'Telha',
      quantidade: 1,
      precoUnitario: 10.0,
      precoCustoUnitario: 5,
    )..produto.target = produto;

    final venda = Venda()
      ..id = 7
      ..itens.add(item);

    final payload = service.montarPayloadNfce(venda);
    final itemPayload =
        (payload['items'] as List).first as Map<String, dynamic>;

    expect(itemPayload['cest'], '1000300');
    expect(itemPayload['icms_origem'], '1');
    expect(itemPayload['icms_situacao_tributaria'], '60');
    expect(itemPayload['pis_situacao_tributaria'], '06');
    expect(itemPayload['cfop'], '5405');
  });
}

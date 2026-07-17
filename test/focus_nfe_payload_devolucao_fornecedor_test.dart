import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/model/produto.dart';
import 'package:sistema_vendas/services/focus_nfe_service.dart';

void main() {
  final config = FocusNfeConfig.homologacao(
    apiToken: 'token-teste',
    cnpjEmitente: '32662298000191',
    inscricaoEstadualEmitente: '123456789',
  );
  final service = FocusNfeService(config: config);

  FocusNfeDestinatarioNfe dest({String uf = 'SP'}) => FocusNfeDestinatarioNfe(
        nome: 'Fabrica Teste',
        documento: '11222333000181',
        inscricaoEstadual: '123456789012',
        indicadorInscricaoEstadual: '1',
        logradouro: 'Av Industrial',
        numero: '500',
        bairro: 'Distrito',
        municipio: 'Sao Paulo',
        codigoMunicipioIbge: '3550308',
        uf: uf,
        cep: '01001000',
      );

  test('devolucao fornecedor: saida, finalidade 4, CFOP 6202 e chave ref', () {
    final produto = Produto(
      codigoInterno: 'CIM',
      nome: 'Cimento',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 18,
      precoVenda: 25,
    );
    const chave =
        '29260132662298000191550010000000011000000019';

    final payload = service.montarPayloadNfeDevolucaoFornecedor(
      chaveNotaCompra: chave,
      destinatario: dest(),
      itensDevolucao: [
        FocusNfeItemDevolucao(
          produto: produto,
          descricao: 'Cimento',
          quantidade: 2,
          valorUnitario: 18.5,
        ),
      ],
      motivo: 'Produto com avaria',
    );

    expect(payload['tipo_documento'], '1');
    expect(payload['finalidade_emissao'], '4');
    expect(payload['natureza_operacao'], 'Devolucao de compra');
    expect(payload['consumidor_final'], '0');
    expect(payload['cnpj_destinatario'], '11222333000181');
    final refs = payload['notas_referenciadas'] as List;
    expect((refs.first as Map)['chave_nfe'], chave);
    final item = (payload['items'] as List).first as Map<String, dynamic>;
    expect(item['cfop'], FiscalConfig.cfopDevolucaoCompraInterestadual);
  });

  test('devolucao fornecedor estadual usa CFOP 5202', () {
    final produto = Produto(
      codigoInterno: 'ARE',
      nome: 'Areia',
      ncm: '25051000',
      quantidadeMinima: 1,
      precoCusto: 5,
      precoVenda: 8,
    );
    final payload = service.montarPayloadNfeDevolucaoFornecedor(
      chaveNotaCompra: '29260132662298000191550010000000011000000019',
      destinatario: dest(uf: FiscalConfig.ufEmitente),
      itensDevolucao: [
        FocusNfeItemDevolucao(
          produto: produto,
          descricao: 'Areia',
          quantidade: 1,
          valorUnitario: 5,
        ),
      ],
    );
    final item = (payload['items'] as List).first as Map<String, dynamic>;
    expect(item['cfop'], FiscalConfig.cfopDevolucaoCompraEstadual);
  });

  test('espelho fabrica sobrescreve CFOP e ICMS no item', () {
    final produto = Produto(
      codigoInterno: 'CIM',
      nome: 'Cimento',
      ncm: '25232910',
      quantidadeMinima: 1,
      precoCusto: 18,
      precoVenda: 25,
    );
    final payload = service.montarPayloadNfeDevolucaoFornecedor(
      chaveNotaCompra: '29260132662298000191550010000000011000000019',
      destinatario: dest(),
      itensDevolucao: [
        FocusNfeItemDevolucao(
          produto: produto,
          descricao: 'Cimento',
          quantidade: 2,
          valorUnitario: 19.9,
          cfopOverride: '5411',
          icmsOrigem: '0',
          icmsSituacaoTributaria: '60',
          icmsBaseCalculo: 39.8,
          icmsAliquota: 0,
          icmsValor: 0,
          icmsBaseCalculoSt: 50,
          icmsValorSt: 7.5,
        ),
      ],
    );
    final item = (payload['items'] as List).first as Map<String, dynamic>;
    expect(item['cfop'], '5411');
    expect(item['icms_situacao_tributaria'], '60');
    expect(item['icms_base_calculo'], '39.80');
    expect(item['icms_base_calculo_st'], '50.00');
    expect(item['icms_valor_st'], '7.50');
    expect(item['valor_unitario_comercial'], '19.90');
  });
}

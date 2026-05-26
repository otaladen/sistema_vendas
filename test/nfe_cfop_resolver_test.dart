import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_cfop_resolver.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto produto({
    String grupo = 'tributado',
    String cfop = '',
  }) =>
      Produto(
        codigoInterno: 'P1',
        nome: 'Prod',
        grupoTributario: grupo,
        cfopVenda: cfop,
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 2,
      );

  test('interestadual tributado usa 6102', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(),
        ufDestinatario: 'SP',
        consumidorFinal: false,
      ),
      FiscalConfig.cfopInterestadualTributadoRevenda,
    );
  });

  test('interestadual ST usa 6403', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(grupo: 'substituicao_tributaria'),
        ufDestinatario: 'RJ',
        consumidorFinal: false,
      ),
      FiscalConfig.cfopInterestadualSt,
    );
  });

  test('BA contribuinte tributado usa 5101', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(),
        ufDestinatario: 'BA',
        consumidorFinal: false,
      ),
      FiscalConfig.cfopEstadualContribuinteTributado,
    );
  });

  test('BA contribuinte ST usa 5401', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(grupo: 'substituicao_tributaria'),
        ufDestinatario: 'BA',
        consumidorFinal: false,
      ),
      FiscalConfig.cfopEstadualContribuinteSt,
    );
  });

  test('BA consumidor final mantem 5102', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(),
        ufDestinatario: 'BA',
        consumidorFinal: true,
      ),
      '5102',
    );
  });

  test('CFOP manual no produto prevalece', () {
    expect(
      NfeCfopResolver.resolver(
        produto: produto(cfop: '5933'),
        ufDestinatario: 'SP',
        consumidorFinal: false,
      ),
      '5933',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/config/fiscal_config.dart';
import 'package:sistema_vendas/domain/fiscal/nfe_cfop_devolucao_fornecedor_resolver.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto produto({String grupo = 'tributado'}) => Produto(
        codigoInterno: 'P1',
        nome: 'Cimento',
        grupoTributario: grupo,
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 2,
      );

  test('estadual comercializacao usa 5202', () {
    expect(
      NfeCfopDevolucaoFornecedorResolver.resolver(
        produto: produto(),
        ufDestinatario: FiscalConfig.ufEmitente,
      ),
      FiscalConfig.cfopDevolucaoCompraEstadual,
    );
  });

  test('interestadual comercializacao usa 6202', () {
    expect(
      NfeCfopDevolucaoFornecedorResolver.resolver(
        produto: produto(),
        ufDestinatario: 'SP',
      ),
      FiscalConfig.cfopDevolucaoCompraInterestadual,
    );
  });

  test('estadual ST usa 5411', () {
    expect(
      NfeCfopDevolucaoFornecedorResolver.resolver(
        produto: produto(grupo: 'substituicao_tributaria'),
        ufDestinatario: FiscalConfig.ufEmitente,
      ),
      FiscalConfig.cfopDevolucaoCompraEstadualSt,
    );
  });

  test('interestadual ST usa 6411', () {
    expect(
      NfeCfopDevolucaoFornecedorResolver.resolver(
        produto: produto(grupo: 'substituicao_tributaria'),
        ufDestinatario: 'MG',
      ),
      FiscalConfig.cfopDevolucaoCompraInterestadualSt,
    );
  });
}

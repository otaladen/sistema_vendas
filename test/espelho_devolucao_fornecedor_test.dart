import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/espelho_devolucao_fornecedor.dart';
import 'package:sistema_vendas/model/item_nota_temporario.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  Produto produto({
    String codigo = 'P1',
    String nome = 'Cimento',
    String ean = '',
  }) =>
      Produto(
        codigoInterno: codigo,
        nome: nome,
        codigoBarras: ean,
        quantidadeMinima: 1,
        precoCusto: 1,
        precoVenda: 2,
      );

  ItemNotaTemporario xmlItem({
    String codigo = 'P1',
    String descricao = 'Cimento',
    String ean = '',
    String cfop = '5202',
    double qCom = 10,
    double vUn = 25,
    double vIcms = 45,
    double vBc = 250,
  }) =>
      ItemNotaTemporario(
        numeroItem: 1,
        codigo: codigo,
        descricao: descricao,
        unidadeComercial: 'UN',
        quantidadeComercial: qCom,
        valorUnitarioComercial: vUn,
        codigoBarras: ean,
        cfop: cfop,
        icmsSituacaoTributaria: '00',
        icmsBaseCalculo: vBc,
        icmsAliquota: 18,
        icmsValor: vIcms,
      );

  test('CFOP compra 1102 vira 5202', () {
    expect(
      EspelhoDevolucaoFornecedorHelper.cfopDevolucaoDeCompra(
        '1102',
        produto: produto(),
        ufFornecedor: 'BA',
      ),
      '5202',
    );
  });

  test('CFOP compra 2102 vira 6202', () {
    expect(
      EspelhoDevolucaoFornecedorHelper.cfopDevolucaoDeCompra(
        '2102',
        produto: produto(),
        ufFornecedor: 'SP',
      ),
      '6202',
    );
  });

  test('CFOP compra 1409 vira 5411 (ST)', () {
    expect(
      EspelhoDevolucaoFornecedorHelper.cfopDevolucaoDeCompra(
        '1409',
        produto: produto(),
        ufFornecedor: 'BA',
      ),
      '5411',
    );
  });

  test('recalculo proporcional metade da entrada', () {
    final e = EspelhoDevolucaoFornecedorItem(
      cfop: '5202',
      valorUnitario: 10,
      icmsAliquota: 18,
    );
    EspelhoDevolucaoFornecedorHelper.recalcularProporcional(
      espelho: e,
      quantidadeDevolver: 5,
      quantidadeEntradaOriginal: 10,
      icmsBaseOrigem: 100,
      icmsValorOrigem: 18,
      icmsBaseStOrigem: 40,
      icmsValorStOrigem: 8,
      ipiValorOrigem: 2,
    );
    expect(e.icmsBaseCalculo, 50);
    expect(e.icmsValor, 9);
    expect(e.icmsBaseCalculoSt, 20);
    expect(e.icmsValorSt, 4);
    expect(e.ipiValor, 1);
  });

  test('casa XML com linha pelo EAN', () {
    final itens = [
      xmlItem(ean: '7891000100103', codigo: 'X'),
      xmlItem(ean: '111', codigo: 'Y', descricao: 'Outro'),
    ];
    final mapa = EspelhoDevolucaoFornecedorHelper.casarItensXmlComLinhas(
      itensXml: itens,
      linhas: [
        (
          index: 0,
          produto: produto(ean: '7891000100103', codigo: 'P99'),
          preco: 25,
          qtdForn: 10,
        ),
      ],
    );
    expect(mapa.length, 1);
    expect(mapa[0]!.codigoBarras, '7891000100103');
  });

  test('aplicarDoItemXml copia CFOP e impostos do espelho', () {
    final e = EspelhoDevolucaoFornecedorItem(cfop: '5202', valorUnitario: 1);
    e.aplicarDoItemXml(
      xmlItem(cfop: '5411', vUn: 19.9, vBc: 39.8, vIcms: 0),
    );
    expect(e.cfop, '5411');
    expect(e.valorUnitario, 19.9);
    expect(e.icmsSituacaoTributaria, '00');
    expect(e.icmsBaseCalculo, 39.8);
  });

  test('quantidade estoque proporcional ao fator da entrada', () {
    expect(
      EspelhoDevolucaoFornecedorHelper.quantidadeEstoqueDoEspelho(
        quantidadeComercialXml: 5,
        quantidadeFornecedorEntrada: 10,
        quantidadeEstoqueEntrada: 20,
        quantidadeMaxima: 20,
      ),
      10,
    );
  });
}

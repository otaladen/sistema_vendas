import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_consulta_multi_deposito_util.dart';
import 'package:sistema_vendas/domain/produto_substitutos_util.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produto({
  int id = 1,
  String localizacao = '',
  int estoqueReal = 49,
  int estoqueReservado = 0,
  int estoqueCd = 0,
  String substitutosIds = '',
}) =>
    Produto(
      id: id,
      codigoInterno: '004025',
      nome: 'Cimento CP II',
      localizacao: localizacao,
      unidade: 'SC',
      precoCusto: 30,
      precoVenda: 50,
      preco1: 50,
      quantidadeMinima: 1,
      estoqueReal: estoqueReal,
      estoqueReservado: estoqueReservado,
      estoqueCd: estoqueCd,
      substitutosIds: substitutosIds,
    );

void main() {
  test('ProdutoSubstitutosUtil parse e format', () {
    expect(ProdutoSubstitutosUtil.parseIds('12; 45,12; 0'), [12, 45]);
    expect(ProdutoSubstitutosUtil.formatIds([12, 45, 12]), '12;45');
  });

  test('rotulo multi deposito inclui loja e CD', () {
    final p = _produto(
      localizacao: 'A-12',
      estoqueReal: 49,
      estoqueCd: 200,
    );
    final rotulo = PdvConsultaMultiDepositoUtil.montarRotuloInsights(p);
    expect(rotulo, contains('Local A-12'));
    expect(rotulo, contains('Loja: 49'));
    expect(rotulo, contains('CD: 200'));
  });

  test('rotulo multi deposito omite CD quando zero', () {
    final rotulo = PdvConsultaMultiDepositoUtil.montarRotuloInsights(
      _produto(estoqueReal: 10),
    );
    expect(rotulo, 'Loja: 10');
    expect(PdvConsultaMultiDepositoUtil.exibirCd(_produto(estoqueCd: 0)), isFalse);
    expect(PdvConsultaMultiDepositoUtil.exibirCd(_produto(estoqueCd: 5)), isTrue);
  });
}

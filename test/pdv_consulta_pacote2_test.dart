import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_consulta_detalhe_linha.dart';
import 'package:sistema_vendas/domain/pdv_estoque_semaforo_util.dart';
import 'package:sistema_vendas/model/produto.dart';

Produto _produto({
  int estoqueReal = 10,
  int estoqueReservado = 0,
  int quantidadeMinima = 2,
}) =>
    Produto(
      codigoInterno: '004025',
      nome: 'Cimento',
      codigoBarras: '789123',
      marca: 'Poty',
      localizacao: 'A-12',
      unidade: 'SC',
      precoCusto: 30,
      precoVenda: 50,
      preco1: 50,
      preco2: 48,
      preco3: 45,
      quantidadeMinima: quantidadeMinima,
      estoqueReal: estoqueReal,
      estoqueReservado: estoqueReservado,
    );

void main() {
  test('detalhe linha junta sku ean marca local embalagem orcamento', () {
    final p = _produto();
    final texto = PdvConsultaDetalheLinhaUtil.montar(
      p,
      quantidadeNoOrcamento: 10,
    );
    expect(texto, contains('SKU 004025'));
    expect(texto, contains('EAN 789123'));
    expect(texto, contains('Poty'));
    expect(texto, contains('Loc. A-12'));
    expect(texto, contains('Orc. 10'));
  });

  test('semaforo vermelho sem estoque', () {
    final p = _produto(estoqueReal: 0);
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p),
      PdvEstoqueSemaforoNivel.vermelho,
    );
  });

  test('semaforo amarelo abaixo do minimo', () {
    final p = _produto(estoqueReal: 1, quantidadeMinima: 5);
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p),
      PdvEstoqueSemaforoNivel.amarelo,
    );
  });

  test('semaforo vermelho quando orcamento excede disponivel', () {
    final p = _produto(estoqueReal: 10, estoqueReservado: 0);
    expect(
      PdvEstoqueSemaforoUtil.nivelDe(p, quantidadeNoOrcamento: 12),
      PdvEstoqueSemaforoNivel.vermelho,
    );
  });

  test('rotulo quantidade lista padroniza grandes numeros', () {
    expect(PdvEstoqueSemaforoUtil.rotuloQuantidadeLista(49), '49');
    expect(PdvEstoqueSemaforoUtil.rotuloQuantidadeLista(420), '420');
    expect(PdvEstoqueSemaforoUtil.rotuloQuantidadeLista(12500), '12,5k');
    expect(PdvEstoqueSemaforoUtil.rotuloQuantidadeLista(99746991), '99,7M');
  });
}

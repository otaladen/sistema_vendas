import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/pdv_obra_calculadora_insercao.dart';
import 'package:sistema_vendas/model/produto.dart';

void main() {
  final areiaM3 = Produto(
    id: 1,
    codigoInterno: 'AREIA',
    nome: 'Areia',
    unidade: 'M3',
    quantidadeMinima: 0,
    precoCusto: 0,
    precoVenda: 0,
    permiteQuantidadeFracionada: true,
  );

  test('areia 0,24 m³ arredonda para 0,50 m³ (nao 1 m³)', () {
    expect(
      PdvObraCalculadoraInsercaoUtil.arredondarVolumeM3ParaVenda(0.24, areiaM3),
      0.50,
    );
  });

  test('areia 0,51 m³ arredonda para 1,00 m³', () {
    expect(
      PdvObraCalculadoraInsercaoUtil.arredondarVolumeM3ParaVenda(0.51, areiaM3),
      1.00,
    );
  });

  test('brita 0,24 m³ arredonda para 0,50 m³', () {
    final britaM3 = Produto(
      id: 3,
      codigoInterno: 'BRITA',
      nome: 'Brita',
      unidade: 'M3',
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
      permiteQuantidadeFracionada: true,
    );
    expect(
      PdvObraCalculadoraInsercaoUtil.arredondarVolumeM3ParaVenda(0.24, britaM3),
      0.50,
    );
  });

  test('passo vem do fator do produto quando configurado', () {
    final prod = Produto(
      id: 2,
      codigoInterno: 'AREIA2',
      nome: 'Areia ensacada',
      unidade: 'M3',
      quantidadePorEmbalagem: 0.25,
      quantidadeMinima: 0,
      precoCusto: 0,
      precoVenda: 0,
    );
    expect(
      PdvObraCalculadoraInsercaoUtil.arredondarVolumeM3ParaVenda(0.20, prod),
      0.25,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/domain/entregas/conferencia_carga_validacao.dart';
import 'package:sistema_vendas/domain/entregas/romaneio_carga_merge.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('ConferenciaCargaValidacao', () {
    test('escopo usa grupo quando ha duas vendas no mesmo carro', () {
      final a = Venda()..id = 1..grupoEntregaFreteId = 9;
      final b = Venda()..id = 2..grupoEntregaFreteId = 9;
      expect(
        ConferenciaCargaValidacao.escopoRomaneio([a, b]),
        'g:9',
      );
    });

    test('escopo usa venda avulsa', () {
      final v = Venda()..id = 42;
      expect(
        ConferenciaCargaValidacao.escopoRomaneio([v]),
        's:42',
      );
    });
  });

  group('RomaneioCargaMerge', () {
    test('lista vazia sem itens de carreto', () {
      final v = Venda()..id = 1;
      expect(RomaneioCargaMerge.montarLinhas([v]), isEmpty);
    });
  });
}

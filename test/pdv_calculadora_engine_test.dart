import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pdv_calculadora_engine.dart';

void main() {
  group('PdvCalculadoraEngine', () {
    test('10 - 2% aplica percentual sobre a base (9,8)', () {
      final c = PdvCalculadoraEngine();
      c.inputDigit('1');
      c.inputDigit('0');
      c.inputOp('-');
      c.inputDigit('2');
      c.percentual();
      expect(c.buffer, '9.8');
      expect(c.expressaoVisivel, contains('10-2%'));
    });

    test('encadeia 15+15+15 na expressão e total parcial', () {
      final c = PdvCalculadoraEngine();
      for (final d in ['1', '5']) {
        c.inputDigit(d);
      }
      c.inputOp('+');
      for (final d in ['1', '5']) {
        c.inputDigit(d);
      }
      c.inputOp('+');
      for (final d in ['1', '5']) {
        c.inputDigit(d);
      }
      expect(c.expressaoVisivel, '15+15+15');
      c.inputOp('+');
      expect(c.buffer, '45');
      expect(c.expressaoVisivel, '15+15+15+');
    });

    test('2% isolado vira 0,02', () {
      final c = PdvCalculadoraEngine();
      c.inputDigit('2');
      c.percentual();
      expect(c.buffer, '0.02');
    });

    test('igual encerra com resultado na fórmula', () {
      final c = PdvCalculadoraEngine();
      c.inputDigit('1');
      c.inputDigit('5');
      c.inputOp('+');
      c.inputDigit('1');
      c.inputDigit('5');
      c.equals();
      expect(c.buffer, '30');
      expect(c.formula, '15+15=');
    });
  });
}

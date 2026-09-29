import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/caixa/caixa_sangria_regra.dart';

void main() {
  group('CaixaSangriaRegra.exigeSupervisor', () {
    test('abaixo do teto nao pede senha', () {
      expect(
        CaixaSangriaRegra.exigeSupervisor(
          valor: 150,
          limiteSemSupervisor: 200,
        ),
        isFalse,
      );
    });

    test('acima do teto pede senha', () {
      expect(
        CaixaSangriaRegra.exigeSupervisor(
          valor: 200.02,
          limiteSemSupervisor: 200,
        ),
        isTrue,
      );
    });

    test('teto zero pede senha em qualquer valor', () {
      expect(
        CaixaSangriaRegra.exigeSupervisor(valor: 0.01, limiteSemSupervisor: 0),
        isTrue,
      );
    });
  });

  group('CaixaSangriaRegra.excedeSaldoGaveta', () {
    test('nao deixa sangrar mais que a gaveta', () {
      expect(
        CaixaSangriaRegra.excedeSaldoGaveta(
          valor: 100.02,
          dinheiroGaveta: 100,
        ),
        isTrue,
      );
    });

    test('aceita sangria igual ao saldo', () {
      expect(
        CaixaSangriaRegra.excedeSaldoGaveta(valor: 80, dinheiroGaveta: 80),
        isFalse,
      );
    });

    test('gaveta zerada recusa qualquer sangria', () {
      expect(
        CaixaSangriaRegra.mensagemSaldoInsuficiente(
          valor: 10,
          dinheiroGaveta: 0,
        ),
        isNotNull,
      );
    });
  });
}

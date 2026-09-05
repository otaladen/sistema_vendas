import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/fiscal_erro_dica_helper.dart';

void main() {
  group('FiscalErroDicaHelper', () {
    test('extrai codigo de rejeicao SEFAZ', () {
      expect(
        FiscalErroDicaHelper.extrairCodigoRejeicao(
          'Rejeicao: 487 - CFOP invalido',
        ),
        '487',
      );
    });

    test('rotuloResumoLista inclui codigo quando presente', () {
      final rotulo = FiscalErroDicaHelper.rotuloResumoLista(
        'Rejeicao 537: Total do desconto difere',
      );
      expect(rotulo, contains('537'));
      expect(rotulo, contains('Rejeicao SEFAZ'));
    });

    test('dicaSolucao para NCM', () {
      final dica = FiscalErroDicaHelper.dicaSolucao('NCM invalido no item 2');
      expect(dica, isNotNull);
      expect(dica!, contains('NCM'));
    });
  });
}

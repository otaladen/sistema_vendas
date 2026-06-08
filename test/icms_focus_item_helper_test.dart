import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/icms_focus_item_helper.dart';

void main() {
  test('CST 00 inclui modBC antes do CST e nao fixa aliquota no app', () {
    final campos = IcmsFocusItemHelper.camposIcmsItem(
      icmsOrigem: '0',
      icmsSituacaoTributaria: '00',
    );

    expect(campos.keys.toList(), [
      'icms_origem',
      'icms_modalidade_base_calculo',
      'icms_situacao_tributaria',
    ]);
    expect(campos['icms_modalidade_base_calculo'], '3');
    expect(campos.containsKey('icms_base_calculo'), isFalse);
    expect(campos.containsKey('icms_aliquota'), isFalse);
    expect(campos.containsKey('icms_valor'), isFalse);
  });

  test('CST 60 nao envia modBC nem base de calculo', () {
    final campos = IcmsFocusItemHelper.camposIcmsItem(
      icmsOrigem: '0',
      icmsSituacaoTributaria: '60',
    );

    expect(campos.keys.toList(), ['icms_origem', 'icms_situacao_tributaria']);
  });
}

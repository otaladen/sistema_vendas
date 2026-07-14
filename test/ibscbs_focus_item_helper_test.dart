import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/fiscal/ibscbs_focus_item_helper.dart';

void main() {
  test('camposItem usa CST 000, cClassTrib 000001 e calcula valores 2026', () {
    final map = IbscbsFocusItemHelper.camposItem(baseCalculo: 100);

    expect(map['ibs_cbs_situacao_tributaria'], '000');
    expect(map['ibs_cbs_classificacao_tributaria'], '000001');
    expect(map['ibs_cbs_base_calculo'], 100.0);
    expect(map['cbs_aliquota'], '0.9');
    expect(map['cbs_valor'], '0.90');
    expect(map['ibs_uf_aliquota'], '0.1');
    expect(map['ibs_uf_valor'], '0.10');
    expect(map['ibs_mun_aliquota'], '0');
    expect(map['ibs_mun_valor'], '0.00');
    expect(map['ibs_valor_total'], '0.10');
  });

  test('camposItem arredonda e aceita base zero', () {
    final map = IbscbsFocusItemHelper.camposItem(baseCalculo: 0);
    expect(map['ibs_cbs_base_calculo'], 0.0);
    expect(map['cbs_valor'], '0.00');
    expect(map['ibs_uf_valor'], '0.00');
  });
}

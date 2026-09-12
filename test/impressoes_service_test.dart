import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/model/config_layout_impressao.dart';
import 'package:sistema_vendas/services/impressoes_service.dart';

void main() {
  test('layout 58mm ajusta largura PDF e divisorias', () {
    const global = ConfigLayoutImpressao(
      larguraPaginaPdfMm: 72,
      margemPaginaMm: 4,
      comprimentoDivisoria: LayoutComprimentoDivisoria.longo,
    );
    final efetivo = ImpressoesService.layoutParaBobinaLocal(
      layoutGlobal: global,
      escPosLargura: '58',
    );
    expect(efetivo.larguraPaginaPdfMm, 52);
    expect(efetivo.margemPaginaMm, 2);
    expect(efetivo.comprimentoDivisoria, LayoutComprimentoDivisoria.curto);
  });

  test('layout 80mm mantem spec padrao da bobina', () {
    const cfg = EmpresaConfig(escPosLargura: '80');
    final efetivo = ImpressoesService.layoutCupomEfetivo(cfg);
    expect(efetivo.larguraPaginaPdfMm, 72);
    expect(efetivo.larguraColunaValorMm, 32);
  });
}

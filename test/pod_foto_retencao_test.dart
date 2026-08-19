import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/pod_foto_retencao.dart';

void main() {
  test('retencao POD: padrao 6 meses e faixas', () {
    expect(PodFotoRetencaoOpcoes.normalizar(null), 180);
    expect(PodFotoRetencaoOpcoes.normalizar(0), 0);
    expect(PodFotoRetencaoOpcoes.normalizar(90), 90);
    expect(PodFotoRetencaoOpcoes.normalizar(180), 180);
    expect(PodFotoRetencaoOpcoes.normalizar(365), 365);
    expect(PodFotoRetencaoOpcoes.normalizar(730), 730);
    expect(PodFotoRetencaoOpcoes.normalizar(100), 90);
    expect(PodFotoRetencaoOpcoes.normalizar(200), 180);
    expect(PodFotoRetencaoOpcoes.rotulo(180), 'Manter 6 meses');
    expect(PodFotoRetencaoOpcoes.rotulo(730), 'Manter 24 meses');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_vendas/data/lote_produto_repository.dart';
import 'package:sistema_vendas/domain/lote_validade_config.dart';
import 'package:sistema_vendas/services/lote_fefo_service.dart';

void main() {
  test('semaforo validade: vencido / critico / atencao / ok', () {
    expect(
      LoteValidadeSemaforoUtil.deDiasRestantes(-1),
      LoteValidadeSemaforo.vermelho,
    );
    expect(
      LoteValidadeSemaforoUtil.deDiasRestantes(10),
      LoteValidadeSemaforo.laranja,
    );
    expect(
      LoteValidadeSemaforoUtil.deDiasRestantes(45),
      LoteValidadeSemaforo.amarelo,
    );
    expect(
      LoteValidadeSemaforoUtil.deDiasRestantes(90),
      LoteValidadeSemaforo.verde,
    );
    expect(
      LoteValidadeSemaforoUtil.deDiasRestantes(null),
      LoteValidadeSemaforo.semValidade,
    );
  });

  test('rotulo patio FEFO agrega lotes', () {
    final txt = LoteFefoService.formatarRotuloRetiradaPatio([
      LoteConsumoSnapshot(
        loteId: 1,
        numeroLote: 'A1',
        dataValidade: DateTime.utc(2026, 8, 15),
        quantidade: 3,
      ),
    ]);
    expect(txt, contains('Retirar do LOTE: A1'));
    expect(txt, contains('15/08/2026'));
    expect(txt, contains('x3'));
  });
}

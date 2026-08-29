import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/ui/theme/app_fundo_id.dart';

void main() {
  test('fromCodigo reconhece estilos e cai no liso', () {
    expect(AppFundoId.fromCodigo('malha'), AppFundoId.malha);
    expect(AppFundoId.fromCodigo('DEGRADE'), AppFundoId.degrade);
    expect(AppFundoId.fromCodigo(null), AppFundoId.liso);
    expect(AppFundoId.fromCodigo('xyz'), AppFundoId.liso);
    expect(AppFundoId.liso.pintaCamada, isFalse);
    expect(AppFundoId.faixa.pintaCamada, isTrue);
  });
}

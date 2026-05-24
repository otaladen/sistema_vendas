import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/caixa_sessao.dart';

void main() {
  test('CaixaSessao toMap/fromMap roundtrip', () {
    final s = CaixaSessao(
      terminalId: 'pc_teste',
      aberto: true,
      operador: 'Maria',
      aberturaEm: DateTime(2026, 5, 23, 10),
      fundoTroco: 100,
      suprimentos: 50,
      sangrias: 20,
      atualizadoEm: DateTime(2026, 5, 23, 18),
    );
    final m = s.toMap();
    final back = CaixaSessao.fromMap(m);
    expect(back.terminalId, 'pc_teste');
    expect(back.aberto, isTrue);
    expect(back.operador, 'Maria');
    expect(back.fundoTroco, 100);
  });
}

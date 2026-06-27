import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/entregas/logistica_entregas.dart';

void main() {
  Venda venda({
    required int id,
    int ordem = 0,
    int grupo = 0,
  }) {
    final v = Venda()..id = id;
    v.ordemEntrega = ordem;
    v.grupoEntregaFreteId = grupo;
    return v;
  }

  group('compararVendaRomaneioMotorista', () {
    test('prioriza ordemEntrega global entre avulsos', () {
      final a = venda(id: 1, ordem: 2);
      final b = venda(id: 2, ordem: 1);
      expect(compararVendaRomaneioMotorista(a, b), greaterThan(0));
      expect(compararVendaRomaneioMotorista(b, a), lessThan(0));
    });

    test('ordem global vence grupo quando ambos tem sequencia', () {
      final grupoPrimeiro = venda(id: 1, ordem: 1, grupo: 10);
      final avulsoDepois = venda(id: 2, ordem: 2, grupo: 0);
      expect(
        compararVendaRomaneioMotorista(grupoPrimeiro, avulsoDepois),
        lessThan(0),
      );
    });
  });

  group('ordenarParadasMotoristaDia', () {
    test('ordena por ordemEntrega crescente', () {
      final lista = ordenarParadasMotoristaDia([
        venda(id: 3, ordem: 3),
        venda(id: 1, ordem: 1),
        venda(id: 2, ordem: 2),
      ]);
      expect(lista.map((v) => v.id).toList(), [1, 2, 3]);
    });
  });
}

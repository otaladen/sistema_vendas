import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/entregas/logistica_entregas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agrupamentoTemClientesDistintos', () {
    Venda venda({required int id, required int clienteId}) {
      final v = Venda()..id = id;
      v.cliente.targetId = clienteId;
      return v;
    }

    test('retorna false com um pedido ou mesmo cliente', () {
      expect(agrupamentoTemClientesDistintos([venda(id: 1, clienteId: 10)]), isFalse);
      expect(
        agrupamentoTemClientesDistintos([
          venda(id: 1, clienteId: 10),
          venda(id: 2, clienteId: 10),
        ]),
        isFalse,
      );
    });

    test('retorna true com clientes diferentes', () {
      expect(
        agrupamentoTemClientesDistintos([
          venda(id: 1, clienteId: 10),
          venda(id: 2, clienteId: 20),
        ]),
        isTrue,
      );
    });
  });
}

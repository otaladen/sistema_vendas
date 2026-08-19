import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/relatorio_performance_entregas.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  Venda entrega({
    required String motorista,
    required String status,
    String veiculo = 'Caminhao 1',
    String obs = '',
    DateTime? marcada,
  }) {
    return Venda(
      status: 'finalizada',
      tipoEntrega: 'loja',
      motoristaEntrega: motorista,
      caminhaoEntrega: veiculo,
      statusEntrega: status,
      observacaoEntrega: obs,
      dataEntregaMarcada: marcada ?? DateTime(2026, 8, 13),
    );
  }

  final periodoIni = DateTime(2026, 8, 1);
  final periodoFim = DateTime(2026, 8, 31);

  test('agrega entregue e insucesso por motorista', () {
    final lista = RelatorioPerformanceEntregas.agregar(
      entregas: [
        entrega(motorista: 'Joao', status: 'entregue'),
        entrega(
          motorista: 'Joao',
          status: 'reagendada',
          obs:
              '[13/08/2026 10:00] ENTREGA_EVENTO_NAO_ENTREGUE por joao: Cliente ausente. Carga retornou para a loja.',
        ),
        entrega(motorista: 'Maria', status: 'entregue'),
      ],
      inicio: periodoIni,
      fim: periodoFim,
      dimensao: 'motorista',
    );
    expect(lista, hasLength(2));
    final joao = lista.firstWhere((e) => e.nome == 'Joao');
    expect(joao.entregues, 1);
    expect(joao.insucessos, 1);
    expect(joao.ausente, 1);
    expect(joao.cargaVoltou, 1);
    expect(joao.taxaSucessoPct, closeTo(50, 0.01));
  });

  test('ignora entrega fora do periodo', () {
    final lista = RelatorioPerformanceEntregas.agregar(
      entregas: [
        entrega(
          motorista: 'Joao',
          status: 'entregue',
          marcada: DateTime(2026, 7, 1),
        ),
      ],
      inicio: periodoIni,
      fim: periodoFim,
      dimensao: 'motorista',
    );
    expect(lista, isEmpty);
  });

  test('dimensao veiculo agrupa pelo caminhao', () {
    final lista = RelatorioPerformanceEntregas.agregar(
      entregas: [
        entrega(motorista: 'A', status: 'entregue', veiculo: 'HR'),
        entrega(motorista: 'B', status: 'entregue', veiculo: 'HR'),
      ],
      inicio: periodoIni,
      fim: periodoFim,
      dimensao: 'veiculo',
    );
    expect(lista, hasLength(1));
    expect(lista.single.entregues, 2);
  });
}

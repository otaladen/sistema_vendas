import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/caixa_fila_orcamento.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  Venda orc({
    required int id,
    required int num,
    required double total,
    DateTime? data,
    String tipoEntrega = 'retirada',
    bool entregaPendente = false,
  }) {
    return Venda(
      id: id,
      numeroOrcamento: num,
      data: data ?? DateTime(2026, 1, 1, 10, 0).add(Duration(hours: id)),
      total: total,
      tipoEntrega: tipoEntrega,
      entregaPendente: entregaPendente,
    );
  }

  test('ordenacao por valor maior', () {
    final lista = [
      orc(id: 1, num: 1, total: 100),
      orc(id: 2, num: 2, total: 500),
      orc(id: 3, num: 3, total: 200),
    ];
    final ord = CaixaFilaOrcamentoHelper.ordenar(
      lista,
      CaixaFilaOrdenacao.valorMaior,
    );
    expect(ord.first.numeroOrcamento, 2);
  });

  test('tempo espera formatado em dias e horas', () {
    final v = orc(
      id: 5,
      num: 5,
      total: 10,
      data: DateTime.now().subtract(const Duration(hours: 50)),
    );
    expect(
      CaixaFilaOrcamentoHelper.formatarTempoEspera(v),
      'ha 2d 2h',
    );
  });

  test('badges so pagamento fiado e misto', () {
    final vEntrega = orc(
      id: 1,
      num: 10,
      total: 50,
      tipoEntrega: 'entrega_loja',
    );
    expect(CaixaFilaOrcamentoHelper.badges(vEntrega), isEmpty);

    final vFiado = Venda(
      id: 2,
      numeroOrcamento: 11,
      data: DateTime.now(),
      total: 80,
      formaPagamento: 'fiado',
    );
    final vMisto = Venda(
      id: 3,
      numeroOrcamento: 12,
      data: DateTime.now(),
      total: 100,
      formaPagamento: 'misto',
    );
    expect(
      CaixaFilaOrcamentoHelper.badges(vFiado).single.rotulo,
      'Fiado',
    );
    expect(
      CaixaFilaOrcamentoHelper.badges(vMisto).single.rotulo,
      'Misto',
    );
  });
}

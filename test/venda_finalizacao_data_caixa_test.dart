import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/listagem_vendas_periodo.dart';
import 'package:sistema_vendas/domain/venda_finalizacao_caixa_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('apos checkout data e finalizadaEm refletem o pagamento no caixa', () {
    final criacaoOrcamento = DateTime.utc(2026, 9, 4, 23, 28);
    final checkout = DateTime.utc(2026, 9, 6, 19, 45);
    final v = Venda(
      data: checkout,
      status: 'finalizada',
      finalizadaEm: checkout,
      total: 150,
    );

    expect(v.data.toUtc(), checkout);
    expect(v.finalizadaEm?.toUtc(), checkout);
    expect(
      VendaFinalizacaoCaixaHelper.momentoFinalizacao(v).toUtc(),
      checkout,
    );
    expect(
      VendaFinalizacaoCaixaHelper.momentoFinalizacao(v).toUtc(),
      isNot(criacaoOrcamento),
    );
  });

  test('orcamento antigo pago hoje entra no filtro Hoje pela data de checkout', () {
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final fim = DateTime.utc(dia.year, dia.month, dia.day, 23, 59, 59, 999);
    final checkout = DateTime.now().toUtc();

    final v = Venda(
      data: checkout,
      status: 'finalizada',
      finalizadaEm: checkout,
      total: 80,
    );

    expect(
      ListagemVendasPeriodo.noIntervaloUtc(
        v,
        inicioUtc: dia.toUtc(),
        fimUtc: fim,
      ),
      isTrue,
    );
  });
}

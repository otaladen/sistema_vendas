import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/listagem_vendas_periodo.dart';
import 'package:sistema_vendas/domain/venda_finalizacao_caixa_helper.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/ui/relatorios/relatorio_periodo.dart';

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
    final limites = calcularLimitesPeriodo(preset: 'hoje');
    final checkout = DateTime.now().toUtc();
    final criacaoOrcamento = checkout.subtract(const Duration(days: 30));

    final v = Venda(
      data: criacaoOrcamento,
      status: 'finalizada',
      finalizadaEm: checkout,
      total: 80,
    );

    expect(
      ListagemVendasPeriodo.noIntervaloUtc(
        v,
        inicioUtc: limites.$1.toUtc(),
        fimUtc: limites.$2.toUtc(),
      ),
      isTrue,
    );
  });
}

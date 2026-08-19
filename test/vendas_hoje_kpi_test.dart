import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/venda_finalizacao_caixa_helper.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  test('momentoFinalizacao prioriza finalizadaEm sobre data do orcamento', () {
    final orcamento = DateTime.utc(2026, 7, 1, 12);
    final fechamento = DateTime.utc(2026, 8, 2, 17, 30);
    final v = Venda(
      data: orcamento,
      status: 'finalizada',
      finalizadaEm: fechamento,
      total: 100,
    );
    final m = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v).toLocal();
    expect(m.year, fechamento.toLocal().year);
    expect(m.month, fechamento.toLocal().month);
    expect(m.day, fechamento.toLocal().day);
  });

  test('orcamento antigo finalizado hoje conta no dia civil local', () {
    final hoje = DateTime.now();
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final fim = dia.add(const Duration(days: 1));
    final v = Venda(
      data: DateTime.now().toUtc().subtract(const Duration(days: 40)),
      status: 'finalizada',
      finalizadaEm: DateTime.now().toUtc(),
      total: 50,
    );
    final m = VendaFinalizacaoCaixaHelper.momentoFinalizacao(v).toLocal();
    expect(!m.isBefore(dia) && m.isBefore(fim), isTrue);
  });
}

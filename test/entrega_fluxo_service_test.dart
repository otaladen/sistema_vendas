import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/model/venda.dart';
import 'package:sistema_vendas/services/entrega_fluxo_service.dart';

void main() {
  Venda vendaComStatus(String status, {String motorista = ''}) {
    return Venda(
      numeroOrcamento: 1,
      data: DateTime(2026, 8, 4),
      total: 10,
      status: 'finalizada',
      statusEntrega: status,
      motoristaEntrega: motorista,
    );
  }

  test('auto-roteiriza apenas pendente/reagendada com motorista', () {
    expect(
      EntregaFluxoService.deveAutoRoteirizar(
        statusEntrega: 'pendente',
        motorista: 'Roberto',
      ),
      isTrue,
    );
    expect(
      EntregaFluxoService.deveAutoRoteirizar(
        statusEntrega: 'reagendada',
        motorista: 'Roberto',
      ),
      isTrue,
    );
    expect(
      EntregaFluxoService.deveAutoRoteirizar(
        statusEntrega: 'roteirizada',
        motorista: 'Roberto',
      ),
      isFalse,
    );
    expect(
      EntregaFluxoService.deveAutoRoteirizar(
        statusEntrega: 'pendente',
        motorista: '',
      ),
      isFalse,
    );
  });

  test('Liberar Saida so em pendente/reagendada/roteirizada', () {
    expect(
      EntregaFluxoService.podeLiberarSaida(vendaComStatus('pendente')),
      isTrue,
    );
    expect(
      EntregaFluxoService.podeLiberarSaida(vendaComStatus('roteirizada')),
      isTrue,
    );
    expect(
      EntregaFluxoService.podeLiberarSaida(vendaComStatus('saiu_entrega')),
      isFalse,
    );
    expect(
      EntregaFluxoService.podeLiberarSaida(vendaComStatus('entregue')),
      isFalse,
    );
  });

  test('vendas do mesmo grupo saem juntas', () {
    final a = Venda(
      id: 1,
      numeroOrcamento: 1,
      status: 'finalizada',
      statusEntrega: 'roteirizada',
      grupoEntregaFreteId: 9,
    );
    final b = Venda(
      id: 2,
      numeroOrcamento: 2,
      status: 'finalizada',
      statusEntrega: 'pendente',
      grupoEntregaFreteId: 9,
    );
    final c = Venda(
      id: 3,
      numeroOrcamento: 3,
      status: 'finalizada',
      statusEntrega: 'roteirizada',
      grupoEntregaFreteId: 8,
    );
    final irmaos = EntregaFluxoService.vendasMesmoDespacho(a, [a, b, c]);
    expect(irmaos.map((v) => v.id), [1, 2]);
  });

  test('sem grupo libera so o pedido', () {
    final a = Venda(
      id: 1,
      numeroOrcamento: 1,
      status: 'finalizada',
      statusEntrega: 'roteirizada',
    );
    final b = Venda(
      id: 2,
      numeroOrcamento: 2,
      status: 'finalizada',
      statusEntrega: 'roteirizada',
    );
    expect(
      EntregaFluxoService.vendasMesmoDespacho(a, [a, b]).single.id,
      1,
    );
  });

  test('Entregue so apos saida', () {
    expect(
      EntregaFluxoService.podeMarcarEntregue(vendaComStatus('saiu_entrega')),
      isTrue,
    );
    expect(
      EntregaFluxoService.podeMarcarEntregue(vendaComStatus('roteirizada')),
      isFalse,
    );
  });
}

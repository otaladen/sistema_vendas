import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/sync/sync_escopo_balcao.dart';
import 'package:sistema_vendas/data/sync/sync_priority.dart';

void main() {
  test('kardex, auditoria e metrica ficam fora do sync continuo', () {
    expect(
      SyncEscopoBalcao.estaForaDoSyncContinuo('movimento_estoque'),
      isTrue,
    );
    expect(
      SyncEscopoBalcao.estaForaDoSyncContinuo('auditoria_evento'),
      isTrue,
    );
    expect(
      SyncEscopoBalcao.estaForaDoSyncContinuo('sugestao_venda_metrica'),
      isTrue,
    );
  });

  test('venda, produto e sugestao cadastrada continuam no sync', () {
    expect(SyncEscopoBalcao.estaForaDoSyncContinuo('venda'), isFalse);
    expect(SyncEscopoBalcao.estaForaDoSyncContinuo('produto'), isFalse);
    expect(
      SyncEscopoBalcao.estaForaDoSyncContinuo('produto_sugestao_venda'),
      isFalse,
    );
    expect(SyncEscopoBalcao.estaForaDoSyncContinuo(null), isFalse);
  });

  test('kardex e metrica nao disparam prioridade alta', () {
    expect(SyncPriorityCatalogo.isAlta('venda'), isTrue);
    expect(SyncPriorityCatalogo.isAlta('movimento_estoque'), isFalse);
    expect(SyncPriorityCatalogo.isBaixa('sugestao_venda_metrica'), isFalse);
    expect(SyncPriorityCatalogo.isBaixa('auditoria_evento'), isFalse);
  });
}

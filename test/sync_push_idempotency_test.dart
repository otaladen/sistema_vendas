import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/sync/sync_push_idempotency.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('salvar e carregar push pendente', () async {
    final batchId = SyncPushIdempotency.gerarBatchId('dev1');
    final mutations = [
      {'entity': 'produto', 'op': 'upsert', 'localId': 1},
    ];
    await SyncPushIdempotency.salvarPendente(
      batchId: batchId,
      mutations: mutations,
    );

    final pendente = await SyncPushIdempotency.carregarPendente();
    expect(pendente, isNotNull);
    expect(pendente!.batchId, batchId);
    expect(pendente.mutations.length, 1);
  });

  test('limpar pendente', () async {
    await SyncPushIdempotency.salvarPendente(
      batchId: 'x',
      mutations: [
        {'entity': 'cliente', 'op': 'upsert', 'localId': 2},
      ],
    );
    await SyncPushIdempotency.limparPendente();
    expect(await SyncPushIdempotency.carregarPendente(), isNull);
  });
}

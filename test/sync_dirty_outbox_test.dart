import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/sync/sync_dirty_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('registrar e listar entradas dirty', () async {
    await SyncDirtyOutbox.registrar(entity: 'produto', entityId: 10);
    await SyncDirtyOutbox.registrar(entity: 'cliente', entityId: 3);

    final lista = await SyncDirtyOutbox.listar();
    expect(lista.length, 2);
    expect(
      lista.map((e) => '${e.entity}:${e.entityId}').toSet(),
      {'produto:10', 'cliente:3'},
    );
  });

  test('limparEnviadas remove ids enviados e wildcard', () async {
    await SyncDirtyOutbox.registrar(entity: 'venda', entityId: 0);
    await SyncDirtyOutbox.registrar(entity: 'venda', entityId: 7);
    await SyncDirtyOutbox.registrar(entity: 'produto', entityId: 5);

    await SyncDirtyOutbox.limparEnviadas([
      {
        'op': 'upsert',
        'entity': 'venda',
        'localId': 7,
      },
      {
        'op': 'upsert',
        'entity': 'venda',
        'localId': 99,
      },
    ]);

    final restantes = await SyncDirtyOutbox.listar();
    expect(restantes.any((e) => e.entity == 'venda'), isFalse);
    expect(restantes.any((e) => e.entity == 'produto' && e.entityId == 5), isTrue);
  });

  test('bootstrap flag', () async {
    expect(await SyncDirtyOutbox.precisaBootstrap(), isTrue);
    await SyncDirtyOutbox.marcarBootstrapConcluido();
    expect(await SyncDirtyOutbox.precisaBootstrap(), isFalse);
  });
}

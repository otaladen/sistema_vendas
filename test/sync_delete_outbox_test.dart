import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/sync/sync_delete_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('registra delete e monta mutacao para push', () async {
    await SyncDeleteOutbox.registrar(
      entity: 'produto',
      entityId: 42,
      localId: 42,
    );

    final mutacoes = await SyncDeleteOutbox.mutacoesParaPush();
    expect(mutacoes.length, 1);
    expect(mutacoes.first['entity'], 'produto');
    expect(mutacoes.first['op'], 'delete');
    expect(mutacoes.first['entityId'], 42);
    expect(mutacoes.first['localId'], 42);
  });

  test('nao duplica mesmo delete pendente', () async {
    await SyncDeleteOutbox.registrar(entity: 'cliente', entityId: 7);
    await SyncDeleteOutbox.registrar(entity: 'cliente', entityId: 7);

    final mutacoes = await SyncDeleteOutbox.mutacoesParaPush();
    expect(mutacoes.length, 1);
  });

  test('limparEnviadas remove apenas deletes confirmados', () async {
    await SyncDeleteOutbox.registrar(entity: 'produto', entityId: 1);
    await SyncDeleteOutbox.registrar(entity: 'produto', entityId: 2);

    await SyncDeleteOutbox.limparEnviadas([
      {'entity': 'produto', 'op': 'delete', 'entityId': 1, 'localId': 1},
    ]);

    final restantes = await SyncDeleteOutbox.mutacoesParaPush();
    expect(restantes.length, 1);
    expect(restantes.first['entityId'], 2);
  });

  test(
    'lista de mutacoes aceita upsert com payload Map<String, dynamic>',
    () async {
      await SyncDeleteOutbox.registrar(entity: 'produto', entityId: 1);
      final mutacoes = <Map<String, dynamic>>[
        ...await SyncDeleteOutbox.mutacoesParaPush(),
      ];

      // Regressao: sem tipagem explicita o List virava Map<String, Object>
      // e este add estourava no bootstrap do sync.
      expect(
        () => mutacoes.add(<String, dynamic>{
          'entity': 'fornecedor_nfe',
          'op': 'upsert',
          'localId': 9,
          'payload': <String, dynamic>{
            'id': 9,
            'cnpj': '123',
            'razaoSocial': 'Teste',
          },
        }),
        returnsNormally,
      );
      expect(mutacoes.length, 2);
      expect(mutacoes.last['payload'], isA<Map<String, dynamic>>());
    },
  );
}

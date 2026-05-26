import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/sync_rede_ajuda.dart';

void main() {
  test('dicasParaErro reconhece token invalido', () {
    final dicas = SyncRedeAjuda.dicasParaErro(
      'Sync recusado pelo servidor (token invalido ou ausente).',
    );
    expect(dicas.first, contains('token'));
  });

  test('dicasParaErro reconhece ObjectBox', () {
    final dicas = SyncRedeAjuda.dicasParaErro(
      'object put failed: ID is higher or equal to internal ID sequence',
    );
    expect(dicas.any((d) => d.contains('cliente')), isTrue);
  });
}

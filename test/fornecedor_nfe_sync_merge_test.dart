import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/sync/fornecedor_nfe_sync_merge.dart';

void main() {
  group('FornecedorNfeSyncMerge', () {
    test('sem local: usa incoming id', () {
      final r = FornecedorNfeSyncMerge.decidir(
        incomingId: 3,
        idLocalPorCnpj: null,
      );
      expect(r.idManter, 3);
      expect(r.aliasIncomingParaLocal, isFalse);
    });

    test('mesmo id: atualiza local', () {
      final r = FornecedorNfeSyncMerge.decidir(
        incomingId: 1,
        idLocalPorCnpj: 1,
      );
      expect(r.idManter, 1);
      expect(r.aliasIncomingParaLocal, isFalse);
    });

    test('cnpj duplicado com ids diferentes: preserva local e cria alias', () {
      final r = FornecedorNfeSyncMerge.decidir(
        incomingId: 3,
        idLocalPorCnpj: 1,
      );
      expect(r.idManter, 1);
      expect(r.aliasIncomingParaLocal, isTrue);
    });
  });

  group('NfeImportadaSyncMerge', () {
    test('chave duplicada com ids diferentes: preserva local', () {
      final r = NfeImportadaSyncMerge.decidir(
        incomingId: 9,
        idLocalPorChave: 2,
      );
      expect(r.idManter, 2);
      expect(r.aliasIncomingParaLocal, isTrue);
    });
  });
}

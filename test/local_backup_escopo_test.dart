import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/local_backup_escopo.dart';

void main() {
  test('parse manifest somente banco', () {
    expect(
      localBackupEscopoFromManifest('somente_banco'),
      LocalBackupEscopo.somenteBanco,
    );
    expect(
      localBackupEscopoFromManifest('banco'),
      LocalBackupEscopo.somenteBanco,
    );
  });

  test('parse cadastro produtos', () {
    expect(
      localBackupEscopoFromManifest('cadastro_produtos'),
      LocalBackupEscopo.cadastroProdutos,
    );
  });

  test('automaticos excluem cadastro', () {
    expect(
      localBackupEscoposAutomaticos(),
      isNot(contains(LocalBackupEscopo.cadastroProdutos)),
    );
  });
}

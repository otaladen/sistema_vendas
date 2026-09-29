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

  test('parse sem imagens', () {
    expect(
      localBackupEscopoFromManifest('sem_imagens'),
      LocalBackupEscopo.semImagens,
    );
    expect(
      localBackupEscopoFromManifest('sem_fotos'),
      LocalBackupEscopo.semImagens,
    );
  });

  test('manifesto sem escopo continua completo', () {
    expect(localBackupEscopoFromManifest(null), LocalBackupEscopo.completo);
    expect(localBackupEscopoFromManifest(''), LocalBackupEscopo.completo);
  });

  test('automaticos colocam o banco diario primeiro e excluem cadastro', () {
    final autos = localBackupEscoposAutomaticos();
    expect(autos.first, LocalBackupEscopo.somenteBanco);
    expect(autos, contains(LocalBackupEscopo.semImagens));
    expect(autos, contains(LocalBackupEscopo.completo));
    expect(autos, isNot(contains(LocalBackupEscopo.cadastroProdutos)));
  });

  test('retencao separa leve e completo', () {
    expect(
      LocalBackupEscopo.somenteBanco.classeRetencao,
      BackupClasseRetencao.leve,
    );
    expect(
      LocalBackupEscopo.semImagens.classeRetencao,
      BackupClasseRetencao.leve,
    );
    expect(
      LocalBackupEscopo.completo.classeRetencao,
      BackupClasseRetencao.completo,
    );
    expect(
      LocalBackupEscopo.cadastroProdutos.classeRetencao,
      BackupClasseRetencao.outro,
    );
  });
}

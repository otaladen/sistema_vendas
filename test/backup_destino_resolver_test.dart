import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/backup_destino_resolver.dart';

void main() {
  group('BackupDestinoResolver.caminhoConfiguradoValido', () {
    test('rejeita vazio e so barras', () {
      expect(BackupDestinoResolver.caminhoConfiguradoValido(null), isFalse);
      expect(BackupDestinoResolver.caminhoConfiguradoValido(''), isFalse);
      expect(BackupDestinoResolver.caminhoConfiguradoValido('   '), isFalse);
      expect(BackupDestinoResolver.caminhoConfiguradoValido(r'\'), isFalse);
      expect(BackupDestinoResolver.caminhoConfiguradoValido(r'\\'), isFalse);
    });

    test('rejeita UNC incompleto', () {
      expect(
        BackupDestinoResolver.caminhoConfiguradoValido(r'\\servidor'),
        isFalse,
      );
      expect(
        BackupDestinoResolver.caminhoConfiguradoValido(r'\\servidor\\'),
        isFalse,
      );
    });

    test('aceita caminho local e UNC completo', () {
      expect(
        BackupDestinoResolver.caminhoConfiguradoValido(r'D:\Backups'),
        isTrue,
      );
      expect(
        BackupDestinoResolver.caminhoConfiguradoValido(
          r'\\servidor\share\backup',
        ),
        isTrue,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/backup_remoto_servidor_service.dart';

void main() {
  test('so aceita zip com prefixo de backup do sistema', () {
    expect(
      BackupRemotoServidorService.ehArquivoZipDeBackup(
        r'D:\Backups\backup_sistema_vendas_20260101_120000.zip',
      ),
      isTrue,
    );
    expect(
      BackupRemotoServidorService.ehArquivoZipDeBackup(r'D:\Backups\outro.zip'),
      isFalse,
    );
    expect(
      BackupRemotoServidorService.ehArquivoZipDeBackup(
        r'D:\Backups\backup_sistema_vendas_20260101_120000.txt',
      ),
      isFalse,
    );
  });

  test('recusa zip fora das pastas de destino', () {
    const raiz = r'D:\Backups\SistemaVendas';
    expect(
      BackupRemotoServidorService.zipDentroDePastasPermitidas(
        r'D:\Backups\SistemaVendas\backup_sistema_vendas_20260101_120000.zip',
        [raiz],
      ),
      isTrue,
    );
    expect(
      BackupRemotoServidorService.zipDentroDePastasPermitidas(
        r'C:\Windows\backup_sistema_vendas_20260101_120000.zip',
        [raiz],
      ),
      isFalse,
    );
  });
}

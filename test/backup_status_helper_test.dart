import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/data/local_backup_validation.dart';
import 'package:sistema_vendas/domain/backup_status_helper.dart';

void main() {
  group('BackupStatusHelper', () {
    test('automatico ativo sem pasta: config incompleta e sem proximo', () {
      final config = EmpresaConfig(
        backupAutomaticoAtivo: true,
        backupAutomaticoPasta: '',
        backupAutomaticoIntervaloMinutos: 60,
      );
      final resumo = BackupStatusHelper.avaliar(
        config: config,
        manual: const BackupRegistroManual(),
      );

      expect(resumo.saude, BackupSaude.configIncompleta);
      expect(resumo.automaticoSemDestino, isTrue);
      expect(resumo.proximoBackupAutomaticoMs, isNull);
      expect(
        BackupStatusHelper.rotuloSaude(resumo.saude),
        'Configuracao incompleta',
      );
    });

    test('automatico ativo com pasta: calcula proximo backup', () {
      final agora = DateTime.now();
      final ultimo = agora.subtract(const Duration(hours: 1));
      final config = EmpresaConfig(
        backupAutomaticoAtivo: true,
        backupAutomaticoPasta: r'D:\Backups',
        backupAutomaticoIntervaloMinutos: 60,
        ultimoBackupAutomaticoMs: ultimo.millisecondsSinceEpoch,
      );
      final resumo = BackupStatusHelper.avaliar(
        config: config,
        manual: const BackupRegistroManual(),
      );

      expect(resumo.automaticoSemDestino, isFalse);
      expect(resumo.proximoBackupAutomaticoMs, isNotNull);
      final proximo = DateTime.fromMillisecondsSinceEpoch(
        resumo.proximoBackupAutomaticoMs!,
      );
      expect(
        proximo.difference(ultimo).inMinutes,
        closeTo(60, 1),
      );
    });

    test('automatico desligado: sem proximo mesmo com pasta', () {
      final config = EmpresaConfig(
        backupAutomaticoAtivo: false,
        backupAutomaticoPasta: r'D:\Backups',
        ultimoBackupAutomaticoMs: DateTime.now().millisecondsSinceEpoch,
      );
      final resumo = BackupStatusHelper.avaliar(
        config: config,
        manual: const BackupRegistroManual(),
      );
      expect(resumo.proximoBackupAutomaticoMs, isNull);
    });
  });

  group('LocalBackupValidation.formatarTamanho', () {
    test('4532 KB vira 4.4 MB', () {
      // 4532 * 1024 bytes
      expect(
        LocalBackupValidation.formatarTamanhoKb(4532),
        '4.4 MB',
      );
    });

    test('bytes pequenos ficam em KB ou B', () {
      expect(LocalBackupValidation.formatarTamanhoBytes(500), '500 B');
      expect(LocalBackupValidation.formatarTamanhoBytes(2048), '2.0 KB');
    });

    test('GB quando >= 1 GB', () {
      expect(
        LocalBackupValidation.formatarTamanhoBytes(2 * 1024 * 1024 * 1024),
        '2.00 GB',
      );
    });
  });
}

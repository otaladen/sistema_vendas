import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_vendas/data/app_config_repository.dart';
import 'package:sistema_vendas/data/sync/sync_local_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sync_local_config_migrado_v1': true,
    });
  });

  test('aplicarSobre usa o maior timestamp entre local e base', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_local_backup_automatico_ultimo_ms', 1000);

    final merged = await SyncLocalConfig.aplicarSobre(
      const EmpresaConfig(ultimoBackupAutomaticoMs: 5000),
    );
    expect(merged.ultimoBackupAutomaticoMs, 5000);

    await prefs.setInt('sync_local_backup_automatico_ultimo_ms', 9000);
    final merged2 = await SyncLocalConfig.aplicarSobre(
      const EmpresaConfig(ultimoBackupAutomaticoMs: 5000),
    );
    expect(merged2.ultimoBackupAutomaticoMs, 9000);
  });

  test(
    'atualizarUltimoBackupAutomaticoMs grava chave global e local',
    () async {
      final repo = AppConfigRepository();
      await repo.atualizarUltimoBackupAutomaticoMs(1234567890);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('config_backup_automatico_ultimo_ms'), 1234567890);
      expect(
        prefs.getInt('sync_local_backup_automatico_ultimo_ms'),
        1234567890,
      );

      final carregado = await repo.carregarEmpresaConfig();
      expect(carregado.ultimoBackupAutomaticoMs, 1234567890);
    },
  );

  test(
    'salvarEmpresaConfig nao diminui ultimoBackupAutomaticoMs ja gravado',
    () async {
      final repo = AppConfigRepository();
      await repo.atualizarUltimoBackupAutomaticoMs(9_000_000);

      final atual = await repo.carregarEmpresaConfig();
      await repo.salvarEmpresaConfig(
        atual.copyWith(ultimoBackupAutomaticoMs: 0),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('config_backup_automatico_ultimo_ms'), 9_000_000);
      expect(
        prefs.getInt('sync_local_backup_automatico_ultimo_ms'),
        9_000_000,
      );
      final carregado = await repo.carregarEmpresaConfig();
      expect(carregado.ultimoBackupAutomaticoMs, 9_000_000);
    },
  );
}

import 'package:shared_preferences/shared_preferences.dart';

import '../app_config_repository.dart';

/// Preferencias locais deste PC — nao entram no payload `empresa_config` (S7).
class SyncLocalConfig {
  SyncLocalConfig._();

  static const _kMigrado = 'sync_local_config_migrado_v1';
  static const _kToken = 'sync_local_rede_sync_token';
  static const _kPorta = 'sync_local_rede_porta_servidor';
  static const _kImpressora = 'sync_local_impressora_padrao';
  static const _kUrl = 'sync_local_rede_servidor_url';
  static const _kModoServidor = 'sync_local_rede_modo_servidor';
  static const _kSyncAtiva = 'sync_local_rede_sincronizacao_ativa';
  static const _kPastaPdf = 'sync_local_pasta_padrao_pdf';
  static const _kLogo = 'sync_local_logo_path';
  static const _kBackupPasta = 'sync_local_backup_automatico_pasta';
  static const _kBackupUltimoMs = 'sync_local_backup_automatico_ultimo_ms';

  static Future<void> migrarLegadoSeNecessario(EmpresaConfig legado) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrado) == true) return;
    await prefs.setString(_kToken, legado.redeSyncToken);
    await prefs.setInt(_kPorta, legado.redePortaServidor);
    await prefs.setString(_kImpressora, legado.impressoraPadrao);
    await prefs.setString(_kUrl, legado.redeServidorUrl);
    await prefs.setBool(_kModoServidor, legado.redeModoServidor);
    await prefs.setBool(_kSyncAtiva, legado.redeSincronizacaoAtiva);
    await prefs.setString(_kPastaPdf, legado.pastaPadraoPdf);
    await prefs.setString(_kLogo, legado.logoPath);
    await prefs.setString(_kBackupPasta, legado.backupAutomaticoPasta);
    await prefs.setInt(_kBackupUltimoMs, legado.ultimoBackupAutomaticoMs);
    await prefs.setBool(_kMigrado, true);
  }

  static Future<EmpresaConfig> aplicarSobre(EmpresaConfig base) async {
    final prefs = await SharedPreferences.getInstance();
    await migrarLegadoSeNecessario(base);
    final porta = prefs.getInt(_kPorta);
    return base.copyWith(
      redeSyncToken: prefs.getString(_kToken) ?? base.redeSyncToken,
      redePortaServidor: porta == null || porta < 1024 || porta > 65535
          ? base.redePortaServidor
          : porta,
      impressoraPadrao:
          prefs.getString(_kImpressora) ?? base.impressoraPadrao,
      redeServidorUrl: prefs.getString(_kUrl) ?? base.redeServidorUrl,
      redeModoServidor:
          prefs.getBool(_kModoServidor) ?? base.redeModoServidor,
      redeSincronizacaoAtiva:
          prefs.getBool(_kSyncAtiva) ?? base.redeSincronizacaoAtiva,
      pastaPadraoPdf: prefs.getString(_kPastaPdf) ?? base.pastaPadraoPdf,
      logoPath: prefs.getString(_kLogo) ?? base.logoPath,
      backupAutomaticoPasta:
          prefs.getString(_kBackupPasta) ?? base.backupAutomaticoPasta,
      ultimoBackupAutomaticoMs:
          prefs.getInt(_kBackupUltimoMs) ?? base.ultimoBackupAutomaticoMs,
    );
  }

  static Future<void> salvarCamposLocais(EmpresaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, config.redeSyncToken.trim());
    await prefs.setInt(
      _kPorta,
      config.redePortaServidor.clamp(1024, 65535),
    );
    await prefs.setString(_kImpressora, config.impressoraPadrao.trim());
    await prefs.setString(_kUrl, config.redeServidorUrl.trim());
    await prefs.setBool(_kModoServidor, config.redeModoServidor);
    await prefs.setBool(_kSyncAtiva, config.redeSincronizacaoAtiva);
    await prefs.setString(_kPastaPdf, config.pastaPadraoPdf.trim());
    await prefs.setString(_kLogo, config.logoPath.trim());
    await prefs.setString(_kBackupPasta, config.backupAutomaticoPasta.trim());
    await prefs.setInt(
      _kBackupUltimoMs,
      config.ultimoBackupAutomaticoMs < 0
          ? 0
          : config.ultimoBackupAutomaticoMs,
    );
    await prefs.setBool(_kMigrado, true);
  }
}

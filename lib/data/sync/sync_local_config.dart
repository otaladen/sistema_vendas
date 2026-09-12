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
  static const _kBackupSegundoDestinoPasta =
      'sync_local_backup_segundo_destino_pasta';
  static const _kAbrirGavetaAutomatica = 'sync_local_abrir_gaveta_automatica';
  static const _kGavetaPino = 'sync_local_gaveta_pino';
  static const _kModoImpressaoBalcao = 'sync_local_modo_impressao_balcao';
  static const _kEscPosLargura = 'sync_local_escpos_largura';
  static const _kEscPosDestino = 'sync_local_escpos_destino';
  static const _kEscPosHost = 'sync_local_escpos_host';
  static const _kEscPosPortaTcp = 'sync_local_escpos_porta_tcp';
  static const _kEscPosPortaCom = 'sync_local_escpos_porta_com';
  static const _kPdvAutoImpressaoFinalizar =
      'sync_local_pdv_auto_impressao_finalizar_v1';

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
    await prefs.setString(
      _kBackupSegundoDestinoPasta,
      legado.backupSegundoDestinoPasta,
    );
    await prefs.setBool(_kMigrado, true);
  }

  static Future<EmpresaConfig> aplicarSobre(EmpresaConfig base) async {
    final prefs = await SharedPreferences.getInstance();
    await migrarLegadoSeNecessario(base);
    // Migracao pontual: pasta do 2o destino passou a ser so local (S7).
    if (!prefs.containsKey(_kBackupSegundoDestinoPasta) &&
        base.backupSegundoDestinoPasta.trim().isNotEmpty) {
      await prefs.setString(
        _kBackupSegundoDestinoPasta,
        base.backupSegundoDestinoPasta.trim(),
      );
    }
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
      // Preferir o maior: o timestamp e gravado em duas chaves (legado + local)
      // e atualizar so uma delas deixava o painel em "Sem backup recente".
      ultimoBackupAutomaticoMs: () {
        final localMs = prefs.getInt(_kBackupUltimoMs) ?? 0;
        final baseMs = base.ultimoBackupAutomaticoMs < 0
            ? 0
            : base.ultimoBackupAutomaticoMs;
        return localMs > baseMs ? localMs : baseMs;
      }(),
      backupSegundoDestinoPasta: prefs.getString(_kBackupSegundoDestinoPasta) ??
          base.backupSegundoDestinoPasta,
      abrirGavetaAutomatica:
          prefs.getBool(_kAbrirGavetaAutomatica) ?? base.abrirGavetaAutomatica,
      gavetaPino: () {
        final p = prefs.getInt(_kGavetaPino);
        if (p == null) return base.gavetaPino;
        return p.clamp(0, 1);
      }(),
      modoImpressaoBalcao: () {
        final m = (prefs.getString(_kModoImpressaoBalcao) ??
                base.modoImpressaoBalcao)
            .trim()
            .toLowerCase();
        return m == 'escpos' ? 'escpos' : 'pdf';
      }(),
      escPosLargura: () {
        final l =
            (prefs.getString(_kEscPosLargura) ?? base.escPosLargura)
                .trim()
                .toLowerCase();
        return (l == '58' || l == '58mm') ? '58' : '80';
      }(),
      escPosDestino: () {
        final d =
            (prefs.getString(_kEscPosDestino) ?? base.escPosDestino)
                .trim()
                .toLowerCase();
        if (d == 'rede' || d == 'tcp' || d == 'ip') return 'rede';
        if (d == 'com' || d == 'serial') return 'com';
        return 'windows';
      }(),
      escPosHost: prefs.getString(_kEscPosHost) ?? base.escPosHost,
      escPosPortaTcp: () {
        final p = prefs.getInt(_kEscPosPortaTcp);
        if (p == null || p < 1 || p > 65535) return base.escPosPortaTcp;
        return p;
      }(),
      escPosPortaCom: prefs.getString(_kEscPosPortaCom) ?? base.escPosPortaCom,
      pdvAutoImpressaoAoFinalizarVenda:
          prefs.getBool(_kPdvAutoImpressaoFinalizar) ??
              base.pdvAutoImpressaoAoFinalizarVenda,
    );
  }

  /// Atualiza so o timestamp local do ultimo backup automatico.
  static Future<void> atualizarUltimoBackupMs(int epochMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBackupUltimoMs, epochMs < 0 ? 0 : epochMs);
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
    final ultimoIncoming = config.ultimoBackupAutomaticoMs < 0
        ? 0
        : config.ultimoBackupAutomaticoMs;
    final ultimoExistente = prefs.getInt(_kBackupUltimoMs) ?? 0;
    await prefs.setInt(
      _kBackupUltimoMs,
      ultimoIncoming > ultimoExistente ? ultimoIncoming : ultimoExistente,
    );
    await prefs.setString(
      _kBackupSegundoDestinoPasta,
      config.backupSegundoDestinoPasta.trim(),
    );
    await prefs.setBool(_kAbrirGavetaAutomatica, config.abrirGavetaAutomatica);
    await prefs.setInt(_kGavetaPino, config.gavetaPino.clamp(0, 1));
    await prefs.setString(
      _kModoImpressaoBalcao,
      config.modoImpressaoBalcao == 'escpos' ? 'escpos' : 'pdf',
    );
    await prefs.setString(
      _kEscPosLargura,
      config.escPosLargura == '58' ? '58' : '80',
    );
    await prefs.setString(_kEscPosDestino, config.escPosDestino);
    await prefs.setString(_kEscPosHost, config.escPosHost.trim());
    await prefs.setInt(
      _kEscPosPortaTcp,
      config.escPosPortaTcp.clamp(1, 65535),
    );
    await prefs.setString(_kEscPosPortaCom, config.escPosPortaCom.trim());
    await prefs.setBool(
      _kPdvAutoImpressaoFinalizar,
      config.pdvAutoImpressaoAoFinalizarVenda,
    );
    await prefs.setBool(_kMigrado, true);
  }
}

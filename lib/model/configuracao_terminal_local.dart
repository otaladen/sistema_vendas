import '../data/app_config_repository.dart';

/// Preferencias de hardware e impressao **deste terminal** (nao sincronizam na LAN).
class ConfiguracaoTerminalLocal {
  const ConfiguracaoTerminalLocal({
    this.impressoraPadrao = '',
    this.pastaPadraoPdf = '',
    this.logoPath = '',
    this.redeSincronizacaoAtiva = false,
    this.redeModoServidor = false,
    this.redePortaServidor = 8788,
    this.redeServidorUrl = '',
    this.redeSyncToken = '',
    this.backupAutomaticoPasta = '',
    this.ultimoBackupAutomaticoMs = 0,
    this.backupSegundoDestinoPasta = '',
    this.abrirGavetaAutomatica = true,
    this.gavetaPino = 0,
    this.modoImpressaoBalcao = 'pdf',
    this.escPosLargura = '80',
    this.escPosDestino = 'windows',
    this.escPosHost = '',
    this.escPosPortaTcp = 9100,
    this.escPosPortaCom = '',
    this.pdvAutoImpressaoAoFinalizarVenda = false,
  });

  final String impressoraPadrao;
  final String pastaPadraoPdf;
  final String logoPath;
  final bool redeSincronizacaoAtiva;
  final bool redeModoServidor;
  final int redePortaServidor;
  final String redeServidorUrl;
  final String redeSyncToken;
  final String backupAutomaticoPasta;
  final int ultimoBackupAutomaticoMs;
  final String backupSegundoDestinoPasta;
  final bool abrirGavetaAutomatica;
  final int gavetaPino;
  final String modoImpressaoBalcao;
  final String escPosLargura;
  final String escPosDestino;
  final String escPosHost;
  final int escPosPortaTcp;
  final String escPosPortaCom;

  /// Imprime cupom automaticamente ao concluir venda no PDV (sem dialogo).
  final bool pdvAutoImpressaoAoFinalizarVenda;

  factory ConfiguracaoTerminalLocal.fromEmpresaConfig(EmpresaConfig c) {
    return ConfiguracaoTerminalLocal(
      impressoraPadrao: c.impressoraPadrao,
      pastaPadraoPdf: c.pastaPadraoPdf,
      logoPath: c.logoPath,
      redeSincronizacaoAtiva: c.redeSincronizacaoAtiva,
      redeModoServidor: c.redeModoServidor,
      redePortaServidor: c.redePortaServidor,
      redeServidorUrl: c.redeServidorUrl,
      redeSyncToken: c.redeSyncToken,
      backupAutomaticoPasta: c.backupAutomaticoPasta,
      ultimoBackupAutomaticoMs: c.ultimoBackupAutomaticoMs,
      backupSegundoDestinoPasta: c.backupSegundoDestinoPasta,
      abrirGavetaAutomatica: c.abrirGavetaAutomatica,
      gavetaPino: c.gavetaPino,
      modoImpressaoBalcao: c.modoImpressaoBalcao,
      escPosLargura: c.escPosLargura,
      escPosDestino: c.escPosDestino,
      escPosHost: c.escPosHost,
      escPosPortaTcp: c.escPosPortaTcp,
      escPosPortaCom: c.escPosPortaCom,
      pdvAutoImpressaoAoFinalizarVenda: c.pdvAutoImpressaoAoFinalizarVenda,
    );
  }

  EmpresaConfig aplicarEm(EmpresaConfig base) {
    return base.copyWith(
      impressoraPadrao: impressoraPadrao,
      pastaPadraoPdf: pastaPadraoPdf,
      logoPath: logoPath,
      redeSincronizacaoAtiva: redeSincronizacaoAtiva,
      redeModoServidor: redeModoServidor,
      redePortaServidor: redePortaServidor,
      redeServidorUrl: redeServidorUrl,
      redeSyncToken: redeSyncToken,
      backupAutomaticoPasta: backupAutomaticoPasta,
      ultimoBackupAutomaticoMs: ultimoBackupAutomaticoMs,
      backupSegundoDestinoPasta: backupSegundoDestinoPasta,
      abrirGavetaAutomatica: abrirGavetaAutomatica,
      gavetaPino: gavetaPino,
      modoImpressaoBalcao: modoImpressaoBalcao,
      escPosLargura: escPosLargura,
      escPosDestino: escPosDestino,
      escPosHost: escPosHost,
      escPosPortaTcp: escPosPortaTcp,
      escPosPortaCom: escPosPortaCom,
      pdvAutoImpressaoAoFinalizarVenda: pdvAutoImpressaoAoFinalizarVenda,
    );
  }

  ConfiguracaoTerminalLocal copyWith({
    String? impressoraPadrao,
    String? pastaPadraoPdf,
    String? logoPath,
    bool? redeSincronizacaoAtiva,
    bool? redeModoServidor,
    int? redePortaServidor,
    String? redeServidorUrl,
    String? redeSyncToken,
    String? backupAutomaticoPasta,
    int? ultimoBackupAutomaticoMs,
    String? backupSegundoDestinoPasta,
    bool? abrirGavetaAutomatica,
    int? gavetaPino,
    String? modoImpressaoBalcao,
    String? escPosLargura,
    String? escPosDestino,
    String? escPosHost,
    int? escPosPortaTcp,
    String? escPosPortaCom,
    bool? pdvAutoImpressaoAoFinalizarVenda,
  }) {
    return ConfiguracaoTerminalLocal(
      impressoraPadrao: impressoraPadrao ?? this.impressoraPadrao,
      pastaPadraoPdf: pastaPadraoPdf ?? this.pastaPadraoPdf,
      logoPath: logoPath ?? this.logoPath,
      redeSincronizacaoAtiva:
          redeSincronizacaoAtiva ?? this.redeSincronizacaoAtiva,
      redeModoServidor: redeModoServidor ?? this.redeModoServidor,
      redePortaServidor: redePortaServidor ?? this.redePortaServidor,
      redeServidorUrl: redeServidorUrl ?? this.redeServidorUrl,
      redeSyncToken: redeSyncToken ?? this.redeSyncToken,
      backupAutomaticoPasta:
          backupAutomaticoPasta ?? this.backupAutomaticoPasta,
      ultimoBackupAutomaticoMs:
          ultimoBackupAutomaticoMs ?? this.ultimoBackupAutomaticoMs,
      backupSegundoDestinoPasta:
          backupSegundoDestinoPasta ?? this.backupSegundoDestinoPasta,
      abrirGavetaAutomatica:
          abrirGavetaAutomatica ?? this.abrirGavetaAutomatica,
      gavetaPino: gavetaPino ?? this.gavetaPino,
      modoImpressaoBalcao: modoImpressaoBalcao ?? this.modoImpressaoBalcao,
      escPosLargura: escPosLargura ?? this.escPosLargura,
      escPosDestino: escPosDestino ?? this.escPosDestino,
      escPosHost: escPosHost ?? this.escPosHost,
      escPosPortaTcp: escPosPortaTcp ?? this.escPosPortaTcp,
      escPosPortaCom: escPosPortaCom ?? this.escPosPortaCom,
      pdvAutoImpressaoAoFinalizarVenda: pdvAutoImpressaoAoFinalizarVenda ??
          this.pdvAutoImpressaoAoFinalizarVenda,
    );
  }
}

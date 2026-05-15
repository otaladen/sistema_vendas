import 'package:shared_preferences/shared_preferences.dart';

import 'sync/sync_write_trigger.dart';

class EmpresaConfig {
  const EmpresaConfig({
    this.nomeLoja = 'LOJA DE MATERIAIS',
    this.telefone = '',
    this.endereco = '',
    this.pastaPadraoPdf = '',
    this.impressoraPadrao = '',
    this.modeloPdf = 'cupom',
    this.rodapeNota = 'Documento nao fiscal',
    this.rodapeOrcamento = 'Este orcamento nao possui valor fiscal.',
    this.logoPath = '',
    this.limiteDivergenciaCaixa = 20,
    this.mostrarCampoDescontoCaixa = true,

    /// Limite de desconto (%) sobre o subtotal de produtos no PDV ao enviar ao caixa (0 = desabilitado).
    this.maxDescontoPercentualPdv = 15,
    this.permitirVendaSemEstoque = true,
    this.whatsappApiVersion = 'v20.0',
    this.whatsappPhoneNumberId = '',
    this.whatsappAccessToken = '',
    this.mensageriaBackendUrl = '',
    this.redeSincronizacaoAtiva = false,
    this.redeServidorUrl = '',
    this.backupAutomaticoAtivo = false,
    this.backupAutomaticoPasta = '',
    this.backupAutomaticoIntervaloMinutos = 1440,
    this.ultimoBackupAutomaticoMs = 0,
  });

  final String nomeLoja;
  final String telefone;
  final String endereco;
  final String pastaPadraoPdf;
  final String impressoraPadrao;
  final String modeloPdf; // cupom | a4
  final String rodapeNota;
  final String rodapeOrcamento;
  final String logoPath;
  final double limiteDivergenciaCaixa;

  /// Quando falso, o painel de desconto rapido some na tela do Caixa.
  final bool mostrarCampoDescontoCaixa;

  /// 0 = vendedor nao pode informar desconto no dialog "Enviar ao caixa"; ate 100 (% sobre subtotal dos produtos).
  final double maxDescontoPercentualPdv;
  final bool permitirVendaSemEstoque;
  final String whatsappApiVersion;
  final String whatsappPhoneNumberId;
  final String whatsappAccessToken;
  final String mensageriaBackendUrl;

  /// Quando verdadeiro, o cliente tentara usar [redeServidorUrl] para sync (quando implementado).
  final bool redeSincronizacaoAtiva;

  /// Ex.: `http://192.168.0.15:8787` — servidor de sincronizacao na LAN.
  final String redeServidorUrl;

  /// Copia periodica dos dados locais para [backupAutomaticoPasta] (quando ativo).
  final bool backupAutomaticoAtivo;

  /// Pasta pai onde serao criadas subpastas `backup_sistema_vendas_*`.
  final String backupAutomaticoPasta;

  /// Intervalo minimo entre backups automaticos (minutos, entre 15 e 10080).
  final int backupAutomaticoIntervaloMinutos;

  /// `DateTime.now().millisecondsSinceEpoch` do ultimo backup automatico bem-sucedido.
  final int ultimoBackupAutomaticoMs;

  EmpresaConfig copyWith({
    String? nomeLoja,
    String? telefone,
    String? endereco,
    String? pastaPadraoPdf,
    String? impressoraPadrao,
    String? modeloPdf,
    String? rodapeNota,
    String? rodapeOrcamento,
    String? logoPath,
    double? limiteDivergenciaCaixa,
    bool? mostrarCampoDescontoCaixa,
    double? maxDescontoPercentualPdv,
    bool? permitirVendaSemEstoque,
    String? whatsappApiVersion,
    String? whatsappPhoneNumberId,
    String? whatsappAccessToken,
    String? mensageriaBackendUrl,
    bool? redeSincronizacaoAtiva,
    String? redeServidorUrl,
    bool? backupAutomaticoAtivo,
    String? backupAutomaticoPasta,
    int? backupAutomaticoIntervaloMinutos,
    int? ultimoBackupAutomaticoMs,
  }) {
    return EmpresaConfig(
      nomeLoja: nomeLoja ?? this.nomeLoja,
      telefone: telefone ?? this.telefone,
      endereco: endereco ?? this.endereco,
      pastaPadraoPdf: pastaPadraoPdf ?? this.pastaPadraoPdf,
      impressoraPadrao: impressoraPadrao ?? this.impressoraPadrao,
      modeloPdf: modeloPdf ?? this.modeloPdf,
      rodapeNota: rodapeNota ?? this.rodapeNota,
      rodapeOrcamento: rodapeOrcamento ?? this.rodapeOrcamento,
      logoPath: logoPath ?? this.logoPath,
      limiteDivergenciaCaixa:
          limiteDivergenciaCaixa ?? this.limiteDivergenciaCaixa,
      mostrarCampoDescontoCaixa:
          mostrarCampoDescontoCaixa ?? this.mostrarCampoDescontoCaixa,
      maxDescontoPercentualPdv:
          maxDescontoPercentualPdv ?? this.maxDescontoPercentualPdv,
      permitirVendaSemEstoque:
          permitirVendaSemEstoque ?? this.permitirVendaSemEstoque,
      whatsappApiVersion: whatsappApiVersion ?? this.whatsappApiVersion,
      whatsappPhoneNumberId:
          whatsappPhoneNumberId ?? this.whatsappPhoneNumberId,
      whatsappAccessToken: whatsappAccessToken ?? this.whatsappAccessToken,
      mensageriaBackendUrl: mensageriaBackendUrl ?? this.mensageriaBackendUrl,
      redeSincronizacaoAtiva:
          redeSincronizacaoAtiva ?? this.redeSincronizacaoAtiva,
      redeServidorUrl: redeServidorUrl ?? this.redeServidorUrl,
      backupAutomaticoAtivo:
          backupAutomaticoAtivo ?? this.backupAutomaticoAtivo,
      backupAutomaticoPasta:
          backupAutomaticoPasta ?? this.backupAutomaticoPasta,
      backupAutomaticoIntervaloMinutos:
          backupAutomaticoIntervaloMinutos ??
              this.backupAutomaticoIntervaloMinutos,
      ultimoBackupAutomaticoMs:
          ultimoBackupAutomaticoMs ?? this.ultimoBackupAutomaticoMs,
    );
  }
}

class AppConfigRepository {
  static const _kNomeLoja = 'config_nome_loja';
  static const _kTelefone = 'config_telefone_loja';
  static const _kEndereco = 'config_endereco_loja';
  static const _kPastaPadraoPdf = 'config_pasta_padrao_pdf';
  static const _kImpressoraPadrao = 'config_impressora_padrao';
  static const _kModeloPdf = 'config_modelo_pdf';
  static const _kRodapeDocumento = 'config_rodape_documento'; // legado
  static const _kRodapeNota = 'config_rodape_nota';
  static const _kRodapeOrcamento = 'config_rodape_orcamento';
  static const _kLogoPath = 'config_logo_path';
  static const _kLimiteDivergenciaCaixa = 'config_limite_divergencia_caixa';
  static const _kMostrarCampoDescontoCaixa =
      'config_mostrar_campo_desconto_caixa';
  static const _kMaxDescontoPercentualPdv =
      'config_max_desconto_percentual_pdv';
  static const _kPermitirVendaSemEstoque = 'config_permitir_venda_sem_estoque';
  static const _kWhatsappApiVersion = 'config_whatsapp_api_version';
  static const _kWhatsappPhoneNumberId = 'config_whatsapp_phone_number_id';
  static const _kWhatsappAccessToken = 'config_whatsapp_access_token';
  static const _kMensageriaBackendUrl = 'config_mensageria_backend_url';
  static const _kRedeSincronizacaoAtiva = 'config_rede_sincronizacao_ativa';
  static const _kRedeServidorUrl = 'config_rede_servidor_url';
  static const _kBackupAutomaticoAtivo = 'config_backup_automatico_ativo';
  static const _kBackupAutomaticoPasta = 'config_backup_automatico_pasta';
  static const _kBackupAutomaticoIntervaloMinutos =
      'config_backup_automatico_intervalo_minutos';
  static const _kBackupAutomaticoUltimoMs =
      'config_backup_automatico_ultimo_ms';
  static const _kMigracaoMotoristaEntregaConcluida =
      'config_migracao_motorista_entrega_concluida';

  Future<EmpresaConfig> carregarEmpresaConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return EmpresaConfig(
      nomeLoja: prefs.getString(_kNomeLoja) ?? 'LOJA DE MATERIAIS',
      telefone: prefs.getString(_kTelefone) ?? '',
      endereco: prefs.getString(_kEndereco) ?? '',
      pastaPadraoPdf: prefs.getString(_kPastaPadraoPdf) ?? '',
      impressoraPadrao: prefs.getString(_kImpressoraPadrao) ?? '',
      modeloPdf: prefs.getString(_kModeloPdf) ?? 'cupom',
      rodapeNota:
          prefs.getString(_kRodapeNota) ??
          prefs.getString(_kRodapeDocumento) ??
          'Documento nao fiscal',
      rodapeOrcamento:
          prefs.getString(_kRodapeOrcamento) ??
          'Este orcamento nao possui valor fiscal.',
      logoPath: prefs.getString(_kLogoPath) ?? '',
      limiteDivergenciaCaixa: prefs.getDouble(_kLimiteDivergenciaCaixa) ?? 20,
      mostrarCampoDescontoCaixa:
          prefs.getBool(_kMostrarCampoDescontoCaixa) ?? true,
      maxDescontoPercentualPdv: () {
        final v = prefs.getDouble(_kMaxDescontoPercentualPdv);
        if (v == null) return 15.0;
        return v.clamp(0.0, 100.0).toDouble();
      }(),
      permitirVendaSemEstoque: prefs.getBool(_kPermitirVendaSemEstoque) ?? true,
      whatsappApiVersion: prefs.getString(_kWhatsappApiVersion) ?? 'v20.0',
      whatsappPhoneNumberId: prefs.getString(_kWhatsappPhoneNumberId) ?? '',
      whatsappAccessToken: prefs.getString(_kWhatsappAccessToken) ?? '',
      mensageriaBackendUrl: prefs.getString(_kMensageriaBackendUrl) ?? '',
      redeSincronizacaoAtiva: prefs.getBool(_kRedeSincronizacaoAtiva) ?? false,
      redeServidorUrl: prefs.getString(_kRedeServidorUrl) ?? '',
      backupAutomaticoAtivo: prefs.getBool(_kBackupAutomaticoAtivo) ?? false,
      backupAutomaticoPasta: prefs.getString(_kBackupAutomaticoPasta) ?? '',
      backupAutomaticoIntervaloMinutos: () {
        final m = prefs.getInt(_kBackupAutomaticoIntervaloMinutos);
        if (m == null || m < 15) return 1440;
        return m.clamp(15, 10080);
      }(),
      ultimoBackupAutomaticoMs: prefs.getInt(_kBackupAutomaticoUltimoMs) ?? 0,
    );
  }

  Future<void> salvarEmpresaConfig(EmpresaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kNomeLoja,
      config.nomeLoja.trim().isEmpty
          ? 'LOJA DE MATERIAIS'
          : config.nomeLoja.trim(),
    );
    await prefs.setString(_kTelefone, config.telefone.trim());
    await prefs.setString(_kEndereco, config.endereco.trim());
    await prefs.setString(_kPastaPadraoPdf, config.pastaPadraoPdf.trim());
    await prefs.setString(_kImpressoraPadrao, config.impressoraPadrao.trim());
    await prefs.setString(
      _kModeloPdf,
      config.modeloPdf.trim().isEmpty ? 'cupom' : config.modeloPdf.trim(),
    );
    final rodapeNota = config.rodapeNota.trim().isEmpty
        ? 'Documento nao fiscal'
        : config.rodapeNota.trim();
    final rodapeOrcamento = config.rodapeOrcamento.trim().isEmpty
        ? 'Este orcamento nao possui valor fiscal.'
        : config.rodapeOrcamento.trim();
    await prefs.setString(_kRodapeNota, rodapeNota);
    await prefs.setString(_kRodapeOrcamento, rodapeOrcamento);
    await prefs.setString(_kRodapeDocumento, rodapeNota);
    await prefs.setString(_kLogoPath, config.logoPath.trim());
    await prefs.setDouble(
      _kLimiteDivergenciaCaixa,
      config.limiteDivergenciaCaixa < 0 ? 0 : config.limiteDivergenciaCaixa,
    );
    await prefs.setBool(
      _kMostrarCampoDescontoCaixa,
      config.mostrarCampoDescontoCaixa,
    );
    await prefs.setDouble(
      _kMaxDescontoPercentualPdv,
      config.maxDescontoPercentualPdv.clamp(0, 100),
    );
    await prefs.setBool(
      _kPermitirVendaSemEstoque,
      config.permitirVendaSemEstoque,
    );
    await prefs.setString(
      _kWhatsappApiVersion,
      config.whatsappApiVersion.trim().isEmpty
          ? 'v20.0'
          : config.whatsappApiVersion.trim(),
    );
    await prefs.setString(
      _kWhatsappPhoneNumberId,
      config.whatsappPhoneNumberId.trim(),
    );
    await prefs.setString(
      _kWhatsappAccessToken,
      config.whatsappAccessToken.trim(),
    );
    await prefs.setString(
      _kMensageriaBackendUrl,
      config.mensageriaBackendUrl.trim(),
    );
    await prefs.setBool(
      _kRedeSincronizacaoAtiva,
      config.redeSincronizacaoAtiva,
    );
    await prefs.setString(_kRedeServidorUrl, config.redeServidorUrl.trim());
    await prefs.setBool(
      _kBackupAutomaticoAtivo,
      config.backupAutomaticoAtivo,
    );
    await prefs.setString(
      _kBackupAutomaticoPasta,
      config.backupAutomaticoPasta.trim(),
    );
    await prefs.setInt(
      _kBackupAutomaticoIntervaloMinutos,
      config.backupAutomaticoIntervaloMinutos.clamp(15, 10080),
    );
    await prefs.setInt(
      _kBackupAutomaticoUltimoMs,
      config.ultimoBackupAutomaticoMs < 0 ? 0 : config.ultimoBackupAutomaticoMs,
    );
    notificarAlteracaoParaRede();
  }

  Future<void> atualizarUltimoBackupAutomaticoMs(int epochMs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kBackupAutomaticoUltimoMs,
      epochMs < 0 ? 0 : epochMs,
    );
  }

  Future<bool> migracaoMotoristaEntregaConcluida() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMigracaoMotoristaEntregaConcluida) ?? false;
  }

  Future<void> marcarMigracaoMotoristaEntregaConcluida() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMigracaoMotoristaEntregaConcluida, true);
  }
}

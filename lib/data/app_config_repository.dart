import 'package:shared_preferences/shared_preferences.dart';

import '../config/fiscal_config.dart';
import '../domain/auditoria_retencao.dart';
import '../services/fiscal_config_store.dart';
import '../model/config_layout_impressao.dart';
import 'sync/sync_local_config.dart';
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
    this.exigirAutorizacaoSegundaViaCupom = true,

    /// Limite de desconto (%) sobre o subtotal de produtos no PDV ao enviar ao caixa (0 = desabilitado).
    this.maxDescontoPercentualPdv = 15,
    this.permitirVendaSemEstoque = true,
    this.whatsappApiVersion = 'v20.0',
    this.whatsappPhoneNumberId = '',
    this.whatsappAccessToken = '',
    this.mensageriaBackendUrl = '',
    this.redeSincronizacaoAtiva = false,
    this.redeModoServidor = false,
    this.redePortaServidor = 8787,
    this.redeServidorUrl = '',
    this.redeSyncToken = '',
    this.backupAutomaticoAtivo = false,
    this.backupAutomaticoPasta = '',
    this.backupAutomaticoIntervaloMinutos = 1440,
    this.ultimoBackupAutomaticoMs = 0,
    this.layoutImpressaoJson = '',
    this.auditoriaRetencaoDias = 90,
    this.margemMinimaPercentualPadrao = 20,
    this.umCaixaAbertoPorLoja = true,
    this.alertasProativosWhatsappAtivos = false,
    this.whatsappDonoNumero = '',
    this.alertasProativosIntervaloMinutos = 120,

    /// Abre gaveta (ESC/POS) apos finalizar pagamento no caixa (config local do PC).
    this.abrirGavetaAutomatica = true,

    /// Pino da gaveta no comando ESC p: 0 ou 1 (Epson/Bematech/Elgin).
    this.gavetaPino = 0,

    /// Regime Focus: 1 = Simples Nacional, 3 = Regime Normal (sincroniza na LAN).
    this.regimeTributarioEmitente = FiscalConfig.regimeTributarioEmitente,
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

  /// Quando falso, segunda via do cupom nao exige login/senha de supervisor.
  final bool exigirAutorizacaoSegundaViaCupom;

  /// 0 = vendedor nao pode informar desconto no dialog "Enviar ao caixa"; ate 100 (% sobre subtotal dos produtos).
  final double maxDescontoPercentualPdv;
  final bool permitirVendaSemEstoque;
  final String whatsappApiVersion;
  final String whatsappPhoneNumberId;
  final String whatsappAccessToken;
  final String mensageriaBackendUrl;

  /// Quando verdadeiro, o app sincroniza com [redeServidorUrl] na LAN.
  final bool redeSincronizacaoAtiva;

  /// Verdadeiro = este PC hospeda o servidor de sync; falso = conecta a outro PC.
  final bool redeModoServidor;

  /// Porta TCP do servidor de sync neste PC (padrao 8787).
  final int redePortaServidor;

    /// Ex.: `http://192.168.0.15:8787` — servidor de sincronizacao na LAN.
    final String redeServidorUrl;

    /// Segredo compartilhado na LAN (header [SyncAuth.headerName]). Vazio = sem auth no servidor.
    final String redeSyncToken;

    /// Copia periodica dos dados locais para [backupAutomaticoPasta] (quando ativo).
  final bool backupAutomaticoAtivo;

  /// Pasta pai onde serao criadas subpastas `backup_sistema_vendas_*`.
  final String backupAutomaticoPasta;

  /// Intervalo minimo entre backups automaticos (minutos, entre 15 e 10080).
  final int backupAutomaticoIntervaloMinutos;

  /// `DateTime.now().millisecondsSinceEpoch` do ultimo backup automatico bem-sucedido.
  final int ultimoBackupAutomaticoMs;

  /// JSON com layout de cupom e orcamento ([LayoutImpressaoEmpresa]).
  final String layoutImpressaoJson;

  /// Retencao do log do sistema: 0 = sem auto-limpeza; 90 ou 180 dias.
  final int auditoriaRetencaoDias;

  /// Margem minima padrao (%) para alerta ao importar NF-e de entrada.
  final double margemMinimaPercentualPadrao;

  /// Quando ativo, so um terminal pode ter caixa aberto na rede.
  final bool umCaixaAbertoPorLoja;

  /// Alertas WhatsApp proativos para o dono (fiado, estoque, caixa).
  final bool alertasProativosWhatsappAtivos;
  final String whatsappDonoNumero;
  final int alertasProativosIntervaloMinutos;

  /// Pulso automatico na gaveta ao confirmar pagamento no caixa (somente Windows).
  final bool abrirGavetaAutomatica;

  /// Conector da gaveta na impressora termica (0 = pin 2, 1 = pin 5 — padrao Epson).
  final int gavetaPino;

  final int regimeTributarioEmitente;

  LayoutImpressaoEmpresa get layoutImpressao =>
      LayoutImpressaoEmpresa.fromJsonString(layoutImpressaoJson);

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
    bool? exigirAutorizacaoSegundaViaCupom,
    double? maxDescontoPercentualPdv,
    bool? permitirVendaSemEstoque,
    String? whatsappApiVersion,
    String? whatsappPhoneNumberId,
    String? whatsappAccessToken,
    String? mensageriaBackendUrl,
    bool? redeSincronizacaoAtiva,
    bool? redeModoServidor,
    int? redePortaServidor,
    String? redeServidorUrl,
    String? redeSyncToken,
    bool? backupAutomaticoAtivo,
    String? backupAutomaticoPasta,
    int? backupAutomaticoIntervaloMinutos,
    int? ultimoBackupAutomaticoMs,
    String? layoutImpressaoJson,
    LayoutImpressaoEmpresa? layoutImpressao,
    int? auditoriaRetencaoDias,
    double? margemMinimaPercentualPadrao,
    bool? umCaixaAbertoPorLoja,
    bool? alertasProativosWhatsappAtivos,
    String? whatsappDonoNumero,
    int? alertasProativosIntervaloMinutos,
    bool? abrirGavetaAutomatica,
    int? gavetaPino,
    int? regimeTributarioEmitente,
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
      exigirAutorizacaoSegundaViaCupom: exigirAutorizacaoSegundaViaCupom ??
          this.exigirAutorizacaoSegundaViaCupom,
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
      redeModoServidor: redeModoServidor ?? this.redeModoServidor,
      redePortaServidor: redePortaServidor ?? this.redePortaServidor,
      redeServidorUrl: redeServidorUrl ?? this.redeServidorUrl,
      redeSyncToken: redeSyncToken ?? this.redeSyncToken,
      backupAutomaticoAtivo:
          backupAutomaticoAtivo ?? this.backupAutomaticoAtivo,
      backupAutomaticoPasta:
          backupAutomaticoPasta ?? this.backupAutomaticoPasta,
      backupAutomaticoIntervaloMinutos:
          backupAutomaticoIntervaloMinutos ??
              this.backupAutomaticoIntervaloMinutos,
      ultimoBackupAutomaticoMs:
          ultimoBackupAutomaticoMs ?? this.ultimoBackupAutomaticoMs,
      layoutImpressaoJson: layoutImpressao != null
          ? layoutImpressao.toJsonString()
          : (layoutImpressaoJson ?? this.layoutImpressaoJson),
      auditoriaRetencaoDias:
          auditoriaRetencaoDias ?? this.auditoriaRetencaoDias,
      margemMinimaPercentualPadrao: margemMinimaPercentualPadrao ??
          this.margemMinimaPercentualPadrao,
      umCaixaAbertoPorLoja:
          umCaixaAbertoPorLoja ?? this.umCaixaAbertoPorLoja,
      alertasProativosWhatsappAtivos: alertasProativosWhatsappAtivos ??
          this.alertasProativosWhatsappAtivos,
      whatsappDonoNumero: whatsappDonoNumero ?? this.whatsappDonoNumero,
      alertasProativosIntervaloMinutos: alertasProativosIntervaloMinutos ??
          this.alertasProativosIntervaloMinutos,
      abrirGavetaAutomatica:
          abrirGavetaAutomatica ?? this.abrirGavetaAutomatica,
      gavetaPino: gavetaPino ?? this.gavetaPino,
      regimeTributarioEmitente: regimeTributarioEmitente != null
          ? regimeTributarioEmitente.clamp(1, 3)
          : this.regimeTributarioEmitente,
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
  static const _kExigirAutorizacaoSegundaViaCupom =
      'config_exigir_autorizacao_segunda_via_cupom';
  static const _kMaxDescontoPercentualPdv =
      'config_max_desconto_percentual_pdv';
  static const _kPermitirVendaSemEstoque = 'config_permitir_venda_sem_estoque';
  static const _kWhatsappApiVersion = 'config_whatsapp_api_version';
  static const _kWhatsappPhoneNumberId = 'config_whatsapp_phone_number_id';
  static const _kWhatsappAccessToken = 'config_whatsapp_access_token';
  static const _kMensageriaBackendUrl = 'config_mensageria_backend_url';
  static const _kRedeSincronizacaoAtiva = 'config_rede_sincronizacao_ativa';
  static const _kRedeModoServidor = 'config_rede_modo_servidor';
  static const _kRedePortaServidor = 'config_rede_porta_servidor';
  static const _kRedeServidorUrl = 'config_rede_servidor_url';
  static const _kRedeSyncToken = 'config_rede_sync_token';
  static const _kBackupAutomaticoAtivo = 'config_backup_automatico_ativo';
  static const _kBackupAutomaticoPasta = 'config_backup_automatico_pasta';
  static const _kBackupAutomaticoIntervaloMinutos =
      'config_backup_automatico_intervalo_minutos';
  static const _kBackupAutomaticoUltimoMs =
      'config_backup_automatico_ultimo_ms';
  static const _kMigracaoMotoristaEntregaConcluida =
      'config_migracao_motorista_entrega_concluida';
  static const _kLayoutImpressaoJson = 'config_layout_impressao_json';
  static const _kAuditoriaRetencaoDias = 'config_auditoria_retencao_dias';
  static const _kMargemMinimaPercentualPadrao =
      'config_margem_minima_percentual_padrao';
  static const _kUmCaixaAbertoPorLoja = 'config_um_caixa_aberto_por_loja';
  static const _kAlertasProativosWhatsapp =
      'config_alertas_proativos_whatsapp';
  static const _kWhatsappDonoNumero = 'config_whatsapp_dono_numero';
  static const _kAlertasProativosIntervaloMin =
      'config_alertas_proativos_intervalo_min';
  static const _kModoImplantacaoLocal = 'sync_modo_implantacao_local_v1';
  static const _kRegimeTributarioEmitente = 'config_regime_tributario_emitente_v1';

  Future<EmpresaConfig> carregarEmpresaConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final base = EmpresaConfig(
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
      exigirAutorizacaoSegundaViaCupom:
          prefs.getBool(_kExigirAutorizacaoSegundaViaCupom) ?? true,
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
      redeModoServidor: prefs.getBool(_kRedeModoServidor) ?? false,
      redePortaServidor: () {
        final p = prefs.getInt(_kRedePortaServidor);
        if (p == null || p < 1024 || p > 65535) return 8787;
        return p;
      }(),
      redeServidorUrl: prefs.getString(_kRedeServidorUrl) ?? '',
      redeSyncToken: prefs.getString(_kRedeSyncToken) ?? '',
      backupAutomaticoAtivo: prefs.getBool(_kBackupAutomaticoAtivo) ?? false,
      backupAutomaticoPasta: prefs.getString(_kBackupAutomaticoPasta) ?? '',
      backupAutomaticoIntervaloMinutos: () {
        final m = prefs.getInt(_kBackupAutomaticoIntervaloMinutos);
        if (m == null || m < 15) return 1440;
        return m.clamp(15, 10080);
      }(),
      ultimoBackupAutomaticoMs: prefs.getInt(_kBackupAutomaticoUltimoMs) ?? 0,
      layoutImpressaoJson: prefs.getString(_kLayoutImpressaoJson) ?? '',
      auditoriaRetencaoDias: () {
        final d = prefs.getInt(_kAuditoriaRetencaoDias);
        if (d == null) return 90;
        if (d <= 0) return 0;
        if (d <= 120) return 90;
        return 180;
      }(),
      margemMinimaPercentualPadrao: () {
        final v = prefs.getDouble(_kMargemMinimaPercentualPadrao);
        if (v == null) return 20.0;
        return v.clamp(0, 99).toDouble();
      }(),
      umCaixaAbertoPorLoja: prefs.getBool(_kUmCaixaAbertoPorLoja) ?? true,
      alertasProativosWhatsappAtivos:
          prefs.getBool(_kAlertasProativosWhatsapp) ?? false,
      whatsappDonoNumero: prefs.getString(_kWhatsappDonoNumero) ?? '',
      alertasProativosIntervaloMinutos: () {
        final m = prefs.getInt(_kAlertasProativosIntervaloMin);
        if (m == null || m < 15) return 120;
        return m.clamp(15, 1440);
      }(),
      regimeTributarioEmitente: () {
        final r = prefs.getInt(_kRegimeTributarioEmitente);
        if (r == null || r < 1 || r > 3) {
          return FiscalConfig.regimeTributarioEmitente;
        }
        return r;
      }(),
    );
    return SyncLocalConfig.aplicarSobre(base);
  }

  Future<void> salvarEmpresaConfig(
    EmpresaConfig config, {
    bool propagarRede = true,
  }) async {
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
    await prefs.setBool(
      _kExigirAutorizacaoSegundaViaCupom,
      config.exigirAutorizacaoSegundaViaCupom,
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
    await prefs.setBool(_kRedeModoServidor, config.redeModoServidor);
    await prefs.setInt(
      _kRedePortaServidor,
      config.redePortaServidor.clamp(1024, 65535),
    );
    await prefs.setString(_kRedeServidorUrl, config.redeServidorUrl.trim());
    await prefs.setString(_kRedeSyncToken, config.redeSyncToken.trim());
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
    await prefs.setString(_kLayoutImpressaoJson, config.layoutImpressaoJson);
    await prefs.setInt(
      _kAuditoriaRetencaoDias,
      AuditoriaRetencaoOpcoes.normalizar(config.auditoriaRetencaoDias),
    );
    await prefs.setDouble(
      _kMargemMinimaPercentualPadrao,
      config.margemMinimaPercentualPadrao.clamp(0, 99),
    );
    await prefs.setBool(_kUmCaixaAbertoPorLoja, config.umCaixaAbertoPorLoja);
    await prefs.setBool(
      _kAlertasProativosWhatsapp,
      config.alertasProativosWhatsappAtivos,
    );
    await prefs.setString(
      _kWhatsappDonoNumero,
      config.whatsappDonoNumero.trim(),
    );
    await prefs.setInt(
      _kAlertasProativosIntervaloMin,
      config.alertasProativosIntervaloMinutos.clamp(15, 1440),
    );
    await prefs.setInt(
      _kRegimeTributarioEmitente,
      config.regimeTributarioEmitente.clamp(1, 3),
    );
    await FiscalConfigStore.aplicarRegimeEmpresa(config.regimeTributarioEmitente);
    await SyncLocalConfig.salvarCamposLocais(config);
    if (propagarRede) {
      notificarAlteracaoParaRede(
        entidade: 'empresa_config',
        entidadeId: 1,
      );
    }
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

  /// Preferencia local deste PC — nao entra em [EmpresaConfig] / sync LAN.
  Future<bool> carregarModoImplantacaoLocal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kModoImplantacaoLocal) ?? false;
  }

  Future<void> salvarModoImplantacaoLocal(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kModoImplantacaoLocal, ativo);
  }
}

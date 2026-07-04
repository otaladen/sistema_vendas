import 'package:shared_preferences/shared_preferences.dart';

import '../config/fiscal_config.dart';
import '../domain/auditoria_retencao.dart';
import '../domain/backup_retencao.dart';
import '../services/fiscal_config_store.dart';
import '../model/config_layout_impressao.dart';
import 'sync/sync_local_config.dart';
import 'sync/sync_write_trigger.dart';

/// Registro local do ultimo backup manual neste PC.
class BackupRegistroManual {
  const BackupRegistroManual({
    this.ultimoMs = 0,
    this.ultimoPath = '',
    this.ultimoTamanhoKb = 0,
    this.pastaPadrao = '',
  });

  final int ultimoMs;
  final String ultimoPath;
  final double ultimoTamanhoKb;
  final String pastaPadrao;
}

/// Ultima falha registrada do backup automatico neste PC.
class BackupFalhaRegistro {
  const BackupFalhaRegistro({
    this.ultimaMs = 0,
    this.mensagem = '',
  });

  final int ultimaMs;
  final String mensagem;

  bool get temFalha => ultimaMs > 0 && mensagem.trim().isNotEmpty;
}

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
    this.backupRetencaoMaxCopias = 15,
    this.backupSegundoDestinoAtivo = false,
    this.backupSegundoDestinoPasta = '',
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

    /// PDV: pula dialog ao adicionar item (qtd 1, retirada, preco do cabecalho).
    this.pdvBalcaoRapido = true,

    /// PDV: envia ao caixa sem dialog de checkout quando dados ja estao no cabecalho.
    this.pdvCheckoutDireto = true,

    /// PDV: apos salvar, so snackbar com numero (sem dialog de impressao).
    this.pdvPularDialogOrcamentoSalvo = true,

    /// Caixa: emite NFC-e em segundo plano e libera fila para proximo cliente.
    this.caixaFiscalNaoBloqueante = true,

    /// Caixa: maximo de orcamentos pendentes carregados na memoria.
    this.caixaLimiteOrcamentosPendentes = 120,

    /// PDV: obriga escolher vendedor antes de enviar orcamento ao caixa.
    this.pdvExigirVendedor = false,

    /// PDV: terminal bloqueado ate o vendedor informar a senha cadastrada.
    this.pdvBloqueioVendedor = false,

    /// PDV: minutos sem atividade para exigir nova identificacao do vendedor (0 = desligado).
    this.pdvBloqueioVendedorInatividadeMinutos = 0,

    /// PDV: apos enviar orcamento ao caixa, exige identificar o vendedor de novo.
    this.pdvBloqueioVendedorAposOrcamento = false,

    /// Calculadora de obra (PDV): IDs de produto padrao (0 = nao configurado).
    this.obraCalcTijoloProdutoId = 0,
    this.obraCalcCimentoProdutoId = 0,
    this.obraCalcAreiaProdutoId = 0,
    this.obraCalcPisoProdutoId = 0,
    this.obraCalcPerdaPadraoPct = 10,
    this.obraCalcPerdaRebocoPct = 15,
    this.obraCalcPerdaPisoPct = 10,
    this.obraCalcEspessuraRebocoMm = 20,
    this.obraCalcEspessuraContrapisoMm = 30,
    this.obraCalcM2PorCaixaPiso = 1.44,
    this.obraCalcGeminiParseAtivo = false,
    this.obraCalcTemplatesJson = '[]',
    this.obraCalcBritaProdutoId = 0,
    this.obraCalcTelhaProdutoId = 0,
    this.obraCalcFerroProdutoId = 0,
    this.obraCalcEspessuraLajeMm = 100,
    this.obraCalcPerdaLajePct = 10,
    this.obraCalcPerdaFundacaoPct = 10,
    this.obraCalcPerdaTelhadoPct = 10,
    this.obraCalcTelhasPorM2 = 16,
    this.obraCalcInclinacaoTelhadoPct = 30,
    this.obraCalcUsarSubstitutoEstoqueZero = true,
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

  /// Quantidade maxima de pastas backup_sistema_vendas_* por pasta de destino (0 = ilimitado).
  final int backupRetencaoMaxCopias;

  /// Espelha cada backup na pasta [backupSegundoDestinoPasta] (rede/nuvem/servidor).
  final bool backupSegundoDestinoAtivo;

  /// Pasta pai do segundo destino (copia espelhada apos cada backup).
  final String backupSegundoDestinoPasta;

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

  final bool pdvBalcaoRapido;
  final bool pdvCheckoutDireto;
  final bool pdvPularDialogOrcamentoSalvo;
  final bool caixaFiscalNaoBloqueante;
  final int caixaLimiteOrcamentosPendentes;
  final bool pdvExigirVendedor;
  final bool pdvBloqueioVendedor;
  final int pdvBloqueioVendedorInatividadeMinutos;
  final bool pdvBloqueioVendedorAposOrcamento;

  /// Produtos padrao da calculadora de obra no PDV (ObjectBox id).
  final int obraCalcTijoloProdutoId;
  final int obraCalcCimentoProdutoId;
  final int obraCalcAreiaProdutoId;
  final int obraCalcPisoProdutoId;

  /// Margem de perda padrao (%) na calculadora de obra.
  final double obraCalcPerdaPadraoPct;
  final double obraCalcPerdaRebocoPct;
  final double obraCalcPerdaPisoPct;
  final double obraCalcEspessuraRebocoMm;
  final double obraCalcEspessuraContrapisoMm;
  final double obraCalcM2PorCaixaPiso;
  final bool obraCalcGeminiParseAtivo;

  /// JSON array de [ObraCalculadoraTemplate].
  final String obraCalcTemplatesJson;
  final int obraCalcBritaProdutoId;
  final int obraCalcTelhaProdutoId;
  final int obraCalcFerroProdutoId;
  final double obraCalcEspessuraLajeMm;
  final double obraCalcPerdaLajePct;
  final double obraCalcPerdaFundacaoPct;
  final double obraCalcPerdaTelhadoPct;
  final double obraCalcTelhasPorM2;
  final double obraCalcInclinacaoTelhadoPct;
  final bool obraCalcUsarSubstitutoEstoqueZero;

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
    int? backupRetencaoMaxCopias,
    bool? backupSegundoDestinoAtivo,
    String? backupSegundoDestinoPasta,
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
    bool? pdvBalcaoRapido,
    bool? pdvCheckoutDireto,
    bool? pdvPularDialogOrcamentoSalvo,
    bool? caixaFiscalNaoBloqueante,
    int? caixaLimiteOrcamentosPendentes,
    bool? pdvExigirVendedor,
    bool? pdvBloqueioVendedor,
    int? pdvBloqueioVendedorInatividadeMinutos,
    bool? pdvBloqueioVendedorAposOrcamento,
    int? obraCalcTijoloProdutoId,
    int? obraCalcCimentoProdutoId,
    int? obraCalcAreiaProdutoId,
    int? obraCalcPisoProdutoId,
    double? obraCalcPerdaPadraoPct,
    double? obraCalcPerdaRebocoPct,
    double? obraCalcPerdaPisoPct,
    double? obraCalcEspessuraRebocoMm,
    double? obraCalcEspessuraContrapisoMm,
    double? obraCalcM2PorCaixaPiso,
    bool? obraCalcGeminiParseAtivo,
    String? obraCalcTemplatesJson,
    int? obraCalcBritaProdutoId,
    int? obraCalcTelhaProdutoId,
    int? obraCalcFerroProdutoId,
    double? obraCalcEspessuraLajeMm,
    double? obraCalcPerdaLajePct,
    double? obraCalcPerdaFundacaoPct,
    double? obraCalcPerdaTelhadoPct,
    double? obraCalcTelhasPorM2,
    double? obraCalcInclinacaoTelhadoPct,
    bool? obraCalcUsarSubstitutoEstoqueZero,
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
      backupRetencaoMaxCopias: backupRetencaoMaxCopias != null
          ? BackupRetencaoOpcoes.normalizar(backupRetencaoMaxCopias)
          : this.backupRetencaoMaxCopias,
      backupSegundoDestinoAtivo:
          backupSegundoDestinoAtivo ?? this.backupSegundoDestinoAtivo,
      backupSegundoDestinoPasta:
          backupSegundoDestinoPasta ?? this.backupSegundoDestinoPasta,
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
      pdvBalcaoRapido: pdvBalcaoRapido ?? this.pdvBalcaoRapido,
      pdvCheckoutDireto: pdvCheckoutDireto ?? this.pdvCheckoutDireto,
      pdvPularDialogOrcamentoSalvo:
          pdvPularDialogOrcamentoSalvo ?? this.pdvPularDialogOrcamentoSalvo,
      caixaFiscalNaoBloqueante:
          caixaFiscalNaoBloqueante ?? this.caixaFiscalNaoBloqueante,
      caixaLimiteOrcamentosPendentes: caixaLimiteOrcamentosPendentes != null
          ? caixaLimiteOrcamentosPendentes.clamp(20, 500)
          : this.caixaLimiteOrcamentosPendentes,
      pdvExigirVendedor: pdvExigirVendedor ?? this.pdvExigirVendedor,
      pdvBloqueioVendedor: pdvBloqueioVendedor ?? this.pdvBloqueioVendedor,
      pdvBloqueioVendedorInatividadeMinutos:
          pdvBloqueioVendedorInatividadeMinutos != null
              ? pdvBloqueioVendedorInatividadeMinutos.clamp(0, 480)
              : this.pdvBloqueioVendedorInatividadeMinutos,
      pdvBloqueioVendedorAposOrcamento: pdvBloqueioVendedorAposOrcamento ??
          this.pdvBloqueioVendedorAposOrcamento,
      obraCalcTijoloProdutoId:
          obraCalcTijoloProdutoId ?? this.obraCalcTijoloProdutoId,
      obraCalcCimentoProdutoId:
          obraCalcCimentoProdutoId ?? this.obraCalcCimentoProdutoId,
      obraCalcAreiaProdutoId:
          obraCalcAreiaProdutoId ?? this.obraCalcAreiaProdutoId,
      obraCalcPisoProdutoId:
          obraCalcPisoProdutoId ?? this.obraCalcPisoProdutoId,
      obraCalcPerdaPadraoPct: obraCalcPerdaPadraoPct != null
          ? obraCalcPerdaPadraoPct.clamp(0, 50)
          : this.obraCalcPerdaPadraoPct,
      obraCalcPerdaRebocoPct: obraCalcPerdaRebocoPct != null
          ? obraCalcPerdaRebocoPct.clamp(0, 50)
          : this.obraCalcPerdaRebocoPct,
      obraCalcPerdaPisoPct: obraCalcPerdaPisoPct != null
          ? obraCalcPerdaPisoPct.clamp(0, 50)
          : this.obraCalcPerdaPisoPct,
      obraCalcEspessuraRebocoMm: obraCalcEspessuraRebocoMm != null
          ? obraCalcEspessuraRebocoMm.clamp(5, 50)
          : this.obraCalcEspessuraRebocoMm,
      obraCalcEspessuraContrapisoMm: obraCalcEspessuraContrapisoMm != null
          ? obraCalcEspessuraContrapisoMm.clamp(10, 80)
          : this.obraCalcEspessuraContrapisoMm,
      obraCalcM2PorCaixaPiso: obraCalcM2PorCaixaPiso != null
          ? obraCalcM2PorCaixaPiso.clamp(0.1, 10)
          : this.obraCalcM2PorCaixaPiso,
      obraCalcGeminiParseAtivo:
          obraCalcGeminiParseAtivo ?? this.obraCalcGeminiParseAtivo,
      obraCalcTemplatesJson:
          obraCalcTemplatesJson ?? this.obraCalcTemplatesJson,
      obraCalcBritaProdutoId:
          obraCalcBritaProdutoId ?? this.obraCalcBritaProdutoId,
      obraCalcTelhaProdutoId:
          obraCalcTelhaProdutoId ?? this.obraCalcTelhaProdutoId,
      obraCalcFerroProdutoId:
          obraCalcFerroProdutoId ?? this.obraCalcFerroProdutoId,
      obraCalcEspessuraLajeMm: obraCalcEspessuraLajeMm != null
          ? obraCalcEspessuraLajeMm.clamp(50, 200)
          : this.obraCalcEspessuraLajeMm,
      obraCalcPerdaLajePct: obraCalcPerdaLajePct != null
          ? obraCalcPerdaLajePct.clamp(0, 50)
          : this.obraCalcPerdaLajePct,
      obraCalcPerdaFundacaoPct: obraCalcPerdaFundacaoPct != null
          ? obraCalcPerdaFundacaoPct.clamp(0, 50)
          : this.obraCalcPerdaFundacaoPct,
      obraCalcPerdaTelhadoPct: obraCalcPerdaTelhadoPct != null
          ? obraCalcPerdaTelhadoPct.clamp(0, 50)
          : this.obraCalcPerdaTelhadoPct,
      obraCalcTelhasPorM2: obraCalcTelhasPorM2 != null
          ? obraCalcTelhasPorM2.clamp(8, 40)
          : this.obraCalcTelhasPorM2,
      obraCalcInclinacaoTelhadoPct: obraCalcInclinacaoTelhadoPct != null
          ? obraCalcInclinacaoTelhadoPct.clamp(0, 60)
          : this.obraCalcInclinacaoTelhadoPct,
      obraCalcUsarSubstitutoEstoqueZero: obraCalcUsarSubstitutoEstoqueZero ??
          this.obraCalcUsarSubstitutoEstoqueZero,
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
  static const _kUltimoBackupManualMs = 'config_ultimo_backup_manual_ms_v1';
  static const _kUltimoBackupManualPath = 'config_ultimo_backup_manual_path_v1';
  static const _kUltimoBackupManualTamanhoKb =
      'config_ultimo_backup_manual_tamanho_kb_v1';
  static const _kBackupManualPastaPadrao = 'config_backup_manual_pasta_padrao_v1';
  static const _kBackupRetencaoMaxCopias = 'config_backup_retencao_max_copias_v1';
  static const _kBackupSegundoDestinoAtivo = 'config_backup_segundo_destino_ativo_v1';
  static const _kBackupSegundoDestinoPasta = 'config_backup_segundo_destino_pasta_v1';
  static const _kBackupAoFecharAtivo = 'config_backup_ao_fechar_ativo_v1';
  static const _kBackupTarefaWindowsHorario = 'config_backup_tarefa_windows_horario_v1';
  static const _kBackupAutomaticoFalhaMs = 'config_backup_automatico_falha_ms_v1';
  static const _kBackupAutomaticoFalhaMsg = 'config_backup_automatico_falha_msg_v1';
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
  static const _kPdvBalcaoRapido = 'config_pdv_balcao_rapido_v1';
  static const _kPdvCheckoutDireto = 'config_pdv_checkout_direto_v1';
  static const _kPdvPularDialogOrcamentoSalvo =
      'config_pdv_pular_dialog_orcamento_salvo_v1';
  static const _kCaixaFiscalNaoBloqueante = 'config_caixa_fiscal_nao_bloqueante_v1';
  static const _kCaixaLimiteOrcamentos = 'config_caixa_limite_orcamentos_v1';
  static const _kPdvExigirVendedor = 'config_pdv_exigir_vendedor_v1';
  static const _kPdvBloqueioVendedor = 'config_pdv_bloqueio_vendedor_v1';
  static const _kPdvBloqueioVendedorInatividadeMinutos =
      'config_pdv_bloqueio_vendedor_inatividade_min_v1';
  static const _kPdvBloqueioVendedorAposOrcamento =
      'config_pdv_bloqueio_vendedor_apos_orcamento_v1';
  static const _kObraCalcTijoloProdutoId = 'config_obra_calc_tijolo_produto_id_v1';
  static const _kObraCalcCimentoProdutoId =
      'config_obra_calc_cimento_produto_id_v1';
  static const _kObraCalcAreiaProdutoId = 'config_obra_calc_areia_produto_id_v1';
  static const _kObraCalcPisoProdutoId = 'config_obra_calc_piso_produto_id_v1';
  static const _kObraCalcPerdaPadraoPct = 'config_obra_calc_perda_padrao_pct_v1';
  static const _kObraCalcPerdaRebocoPct = 'config_obra_calc_perda_reboco_pct_v1';
  static const _kObraCalcPerdaPisoPct = 'config_obra_calc_perda_piso_pct_v1';
  static const _kObraCalcEspessuraRebocoMm = 'config_obra_calc_esp_reboco_mm_v1';
  static const _kObraCalcEspessuraContrapisoMm =
      'config_obra_calc_esp_contrapiso_mm_v1';
  static const _kObraCalcM2PorCaixaPiso = 'config_obra_calc_m2_por_caixa_v1';
  static const _kObraCalcGeminiParseAtivo = 'config_obra_calc_gemini_parse_v1';
  static const _kObraCalcTemplatesJson = 'config_obra_calc_templates_json_v1';
  static const _kObraCalcBritaProdutoId = 'config_obra_calc_brita_produto_id_v1';
  static const _kObraCalcTelhaProdutoId = 'config_obra_calc_telha_produto_id_v1';
  static const _kObraCalcFerroProdutoId = 'config_obra_calc_ferro_produto_id_v1';
  static const _kObraCalcEspessuraLajeMm = 'config_obra_calc_esp_laje_mm_v1';
  static const _kObraCalcPerdaLajePct = 'config_obra_calc_perda_laje_pct_v1';
  static const _kObraCalcPerdaFundacaoPct = 'config_obra_calc_perda_fund_pct_v1';
  static const _kObraCalcPerdaTelhadoPct = 'config_obra_calc_perda_telh_pct_v1';
  static const _kObraCalcTelhasPorM2 = 'config_obra_calc_telhas_m2_v1';
  static const _kObraCalcInclinacaoTelhadoPct =
      'config_obra_calc_incl_telh_pct_v1';
  static const _kObraCalcUsarSubstitutoEstoqueZero =
      'config_obra_calc_subst_estoque_v1';

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
      backupRetencaoMaxCopias: BackupRetencaoOpcoes.normalizar(
        prefs.getInt(_kBackupRetencaoMaxCopias),
      ),
      backupSegundoDestinoAtivo:
          prefs.getBool(_kBackupSegundoDestinoAtivo) ?? false,
      backupSegundoDestinoPasta:
          prefs.getString(_kBackupSegundoDestinoPasta) ?? '',
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
      pdvBalcaoRapido: prefs.getBool(_kPdvBalcaoRapido) ?? true,
      pdvCheckoutDireto: prefs.getBool(_kPdvCheckoutDireto) ?? true,
      pdvPularDialogOrcamentoSalvo:
          prefs.getBool(_kPdvPularDialogOrcamentoSalvo) ?? true,
      caixaFiscalNaoBloqueante:
          prefs.getBool(_kCaixaFiscalNaoBloqueante) ?? true,
      caixaLimiteOrcamentosPendentes: () {
        final n = prefs.getInt(_kCaixaLimiteOrcamentos);
        if (n == null || n < 20) return 120;
        return n.clamp(20, 500);
      }(),
      pdvExigirVendedor: prefs.getBool(_kPdvExigirVendedor) ?? false,
      pdvBloqueioVendedor: prefs.getBool(_kPdvBloqueioVendedor) ?? false,
      pdvBloqueioVendedorInatividadeMinutos:
          prefs.getInt(_kPdvBloqueioVendedorInatividadeMinutos) ?? 0,
      pdvBloqueioVendedorAposOrcamento:
          prefs.getBool(_kPdvBloqueioVendedorAposOrcamento) ?? false,
      obraCalcTijoloProdutoId: prefs.getInt(_kObraCalcTijoloProdutoId) ?? 0,
      obraCalcCimentoProdutoId: prefs.getInt(_kObraCalcCimentoProdutoId) ?? 0,
      obraCalcAreiaProdutoId: prefs.getInt(_kObraCalcAreiaProdutoId) ?? 0,
      obraCalcPisoProdutoId: prefs.getInt(_kObraCalcPisoProdutoId) ?? 0,
      obraCalcPerdaPadraoPct: () {
        final v = prefs.getDouble(_kObraCalcPerdaPadraoPct);
        if (v == null) return 10.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaRebocoPct: () {
        final v = prefs.getDouble(_kObraCalcPerdaRebocoPct);
        if (v == null) return 15.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaPisoPct: () {
        final v = prefs.getDouble(_kObraCalcPerdaPisoPct);
        if (v == null) return 10.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcEspessuraRebocoMm: () {
        final v = prefs.getDouble(_kObraCalcEspessuraRebocoMm);
        if (v == null) return 20.0;
        return v.clamp(5, 50).toDouble();
      }(),
      obraCalcEspessuraContrapisoMm: () {
        final v = prefs.getDouble(_kObraCalcEspessuraContrapisoMm);
        if (v == null) return 30.0;
        return v.clamp(10, 80).toDouble();
      }(),
      obraCalcM2PorCaixaPiso: () {
        final v = prefs.getDouble(_kObraCalcM2PorCaixaPiso);
        if (v == null) return 1.44;
        return v.clamp(0.1, 10).toDouble();
      }(),
      obraCalcGeminiParseAtivo:
          prefs.getBool(_kObraCalcGeminiParseAtivo) ?? false,
      obraCalcTemplatesJson:
          prefs.getString(_kObraCalcTemplatesJson) ?? '[]',
      obraCalcBritaProdutoId: prefs.getInt(_kObraCalcBritaProdutoId) ?? 0,
      obraCalcTelhaProdutoId: prefs.getInt(_kObraCalcTelhaProdutoId) ?? 0,
      obraCalcFerroProdutoId: prefs.getInt(_kObraCalcFerroProdutoId) ?? 0,
      obraCalcEspessuraLajeMm: () {
        final v = prefs.getDouble(_kObraCalcEspessuraLajeMm);
        if (v == null) return 100.0;
        return v.clamp(50, 200).toDouble();
      }(),
      obraCalcPerdaLajePct: () {
        final v = prefs.getDouble(_kObraCalcPerdaLajePct);
        if (v == null) return 10.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaFundacaoPct: () {
        final v = prefs.getDouble(_kObraCalcPerdaFundacaoPct);
        if (v == null) return 10.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcPerdaTelhadoPct: () {
        final v = prefs.getDouble(_kObraCalcPerdaTelhadoPct);
        if (v == null) return 10.0;
        return v.clamp(0, 50).toDouble();
      }(),
      obraCalcTelhasPorM2: () {
        final v = prefs.getDouble(_kObraCalcTelhasPorM2);
        if (v == null) return 16.0;
        return v.clamp(8, 40).toDouble();
      }(),
      obraCalcInclinacaoTelhadoPct: () {
        final v = prefs.getDouble(_kObraCalcInclinacaoTelhadoPct);
        if (v == null) return 30.0;
        return v.clamp(0, 60).toDouble();
      }(),
      obraCalcUsarSubstitutoEstoqueZero:
          prefs.getBool(_kObraCalcUsarSubstitutoEstoqueZero) ?? true,
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
    await prefs.setInt(
      _kBackupRetencaoMaxCopias,
      BackupRetencaoOpcoes.normalizar(config.backupRetencaoMaxCopias),
    );
    await prefs.setBool(
      _kBackupSegundoDestinoAtivo,
      config.backupSegundoDestinoAtivo,
    );
    await prefs.setString(
      _kBackupSegundoDestinoPasta,
      config.backupSegundoDestinoPasta.trim(),
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
    await prefs.setBool(_kPdvBalcaoRapido, config.pdvBalcaoRapido);
    await prefs.setBool(_kPdvCheckoutDireto, config.pdvCheckoutDireto);
    await prefs.setBool(
      _kPdvPularDialogOrcamentoSalvo,
      config.pdvPularDialogOrcamentoSalvo,
    );
    await prefs.setBool(
      _kCaixaFiscalNaoBloqueante,
      config.caixaFiscalNaoBloqueante,
    );
    await prefs.setInt(
      _kCaixaLimiteOrcamentos,
      config.caixaLimiteOrcamentosPendentes.clamp(20, 500),
    );
    await prefs.setBool(_kPdvExigirVendedor, config.pdvExigirVendedor);
    await prefs.setBool(_kPdvBloqueioVendedor, config.pdvBloqueioVendedor);
    await prefs.setInt(
      _kPdvBloqueioVendedorInatividadeMinutos,
      config.pdvBloqueioVendedorInatividadeMinutos.clamp(0, 480),
    );
    await prefs.setBool(
      _kPdvBloqueioVendedorAposOrcamento,
      config.pdvBloqueioVendedorAposOrcamento,
    );
    await prefs.setInt(
      _kObraCalcTijoloProdutoId,
      config.obraCalcTijoloProdutoId < 0 ? 0 : config.obraCalcTijoloProdutoId,
    );
    await prefs.setInt(
      _kObraCalcCimentoProdutoId,
      config.obraCalcCimentoProdutoId < 0 ? 0 : config.obraCalcCimentoProdutoId,
    );
    await prefs.setInt(
      _kObraCalcAreiaProdutoId,
      config.obraCalcAreiaProdutoId < 0 ? 0 : config.obraCalcAreiaProdutoId,
    );
    await prefs.setInt(
      _kObraCalcPisoProdutoId,
      config.obraCalcPisoProdutoId < 0 ? 0 : config.obraCalcPisoProdutoId,
    );
    await prefs.setDouble(
      _kObraCalcPerdaPadraoPct,
      config.obraCalcPerdaPadraoPct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcPerdaRebocoPct,
      config.obraCalcPerdaRebocoPct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcPerdaPisoPct,
      config.obraCalcPerdaPisoPct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcEspessuraRebocoMm,
      config.obraCalcEspessuraRebocoMm.clamp(5, 50),
    );
    await prefs.setDouble(
      _kObraCalcEspessuraContrapisoMm,
      config.obraCalcEspessuraContrapisoMm.clamp(10, 80),
    );
    await prefs.setDouble(
      _kObraCalcM2PorCaixaPiso,
      config.obraCalcM2PorCaixaPiso.clamp(0.1, 10),
    );
    await prefs.setBool(
      _kObraCalcGeminiParseAtivo,
      config.obraCalcGeminiParseAtivo,
    );
    await prefs.setString(
      _kObraCalcTemplatesJson,
      config.obraCalcTemplatesJson.trim().isEmpty
          ? '[]'
          : config.obraCalcTemplatesJson,
    );
    await prefs.setInt(
      _kObraCalcBritaProdutoId,
      config.obraCalcBritaProdutoId < 0 ? 0 : config.obraCalcBritaProdutoId,
    );
    await prefs.setInt(
      _kObraCalcTelhaProdutoId,
      config.obraCalcTelhaProdutoId < 0 ? 0 : config.obraCalcTelhaProdutoId,
    );
    await prefs.setInt(
      _kObraCalcFerroProdutoId,
      config.obraCalcFerroProdutoId < 0 ? 0 : config.obraCalcFerroProdutoId,
    );
    await prefs.setDouble(
      _kObraCalcEspessuraLajeMm,
      config.obraCalcEspessuraLajeMm.clamp(50, 200),
    );
    await prefs.setDouble(
      _kObraCalcPerdaLajePct,
      config.obraCalcPerdaLajePct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcPerdaFundacaoPct,
      config.obraCalcPerdaFundacaoPct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcPerdaTelhadoPct,
      config.obraCalcPerdaTelhadoPct.clamp(0, 50),
    );
    await prefs.setDouble(
      _kObraCalcTelhasPorM2,
      config.obraCalcTelhasPorM2.clamp(8, 40),
    );
    await prefs.setDouble(
      _kObraCalcInclinacaoTelhadoPct,
      config.obraCalcInclinacaoTelhadoPct.clamp(0, 60),
    );
    await prefs.setBool(
      _kObraCalcUsarSubstitutoEstoqueZero,
      config.obraCalcUsarSubstitutoEstoqueZero,
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

  Future<BackupRegistroManual> carregarRegistroBackupManual() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupRegistroManual(
      ultimoMs: prefs.getInt(_kUltimoBackupManualMs) ?? 0,
      ultimoPath: prefs.getString(_kUltimoBackupManualPath) ?? '',
      ultimoTamanhoKb: prefs.getDouble(_kUltimoBackupManualTamanhoKb) ?? 0,
      pastaPadrao: prefs.getString(_kBackupManualPastaPadrao) ?? '',
    );
  }

  Future<void> salvarRegistroBackupManual({
    required int ultimoMs,
    required String ultimoPath,
    required double ultimoTamanhoKb,
    required String pastaPadrao,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUltimoBackupManualMs, ultimoMs < 0 ? 0 : ultimoMs);
    await prefs.setString(_kUltimoBackupManualPath, ultimoPath.trim());
    await prefs.setDouble(_kUltimoBackupManualTamanhoKb, ultimoTamanhoKb);
    if (pastaPadrao.trim().isNotEmpty) {
      await prefs.setString(_kBackupManualPastaPadrao, pastaPadrao.trim());
    }
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

  /// Preferencia local deste PC — nao entra em sync LAN.
  Future<bool> carregarBackupAoFecharAtivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBackupAoFecharAtivo) ?? false;
  }

  Future<void> salvarBackupAoFecharAtivo(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackupAoFecharAtivo, ativo);
  }

  Future<BackupFalhaRegistro> carregarFalhaBackupAutomatico() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupFalhaRegistro(
      ultimaMs: prefs.getInt(_kBackupAutomaticoFalhaMs) ?? 0,
      mensagem: prefs.getString(_kBackupAutomaticoFalhaMsg) ?? '',
    );
  }

  Future<void> registrarFalhaBackupAutomatico(String mensagem) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kBackupAutomaticoFalhaMs,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(_kBackupAutomaticoFalhaMsg, mensagem.trim());
  }

  Future<void> limparFalhaBackupAutomatico() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBackupAutomaticoFalhaMs, 0);
    await prefs.setString(_kBackupAutomaticoFalhaMsg, '');
  }

  Future<String> carregarHorarioTarefaBackupWindows() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBackupTarefaWindowsHorario) ?? '22:00';
  }

  Future<void> salvarHorarioTarefaBackupWindows(String horario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackupTarefaWindowsHorario, horario.trim());
  }
}

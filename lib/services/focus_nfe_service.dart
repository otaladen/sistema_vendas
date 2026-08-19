// =============================================================================
// ARQUITETURA — LEIA ANTES DE ALTERAR
// =============================================================================
// Este servico e EXCLUSIVAMENTE de faturamento eletronico (Focus NFe / SEFAZ).
// PROIBIDO: importar ObjectBox, produtoBox, GerenciadorEstoqueService ou qualquer
// codigo que altere estoqueReal / estoqueReservado. NFC-e e NF-e de venda NAO
// movimentam estoque fisico no ERP (baixa no cupom nao fiscal).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../config/fiscal_config.dart';
import '../domain/fiscal/focus_documento_fiscal_url.dart';
import '../domain/fiscal/icms_focus_item_helper.dart';
import '../domain/fiscal/ibscbs_focus_item_helper.dart';
import '../domain/fiscal/venda_documento_fiscal_mutex.dart';
import '../domain/fiscal/nfe_cfop_devolucao_fornecedor_resolver.dart';
import '../domain/fiscal/nfe_cfop_devolucao_resolver.dart';
import '../domain/fiscal/nfe_cfop_resolver.dart';
import '../domain/fiscal/nfe_cobranca_helper.dart';
import '../domain/fiscal/produto_fiscal_catalog.dart';
import '../domain/produto_nome_exibicao.dart';
import '../domain/pagamento_orcamento.dart';
import '../domain/venda_documento_rotulo_helper.dart';
import '../model/cliente.dart';
import '../model/item_nota_temporario.dart';
import '../model/item_venda.dart';
import '../model/produto.dart';
import '../model/venda.dart';
import 'fiscal_service.dart';

/// Ambiente da API Focus NFe.
enum FocusNfeAmbiente {
  homologacao,
  producao,
}

/// Tipo de emissao SEFAZ (ide.tpEmis) — enviado no payload.
///
/// NFC-e em contingencia offline: combine [tipoEmissaoContingenciaOfflineNfce]
/// com [FocusNfeFormaEmissaoUrl.offline] na URL (exigencia Focus).
class FocusNfeEmissaoSefaz {
  FocusNfeEmissaoSefaz._();

  /// Emissao normal.
  static const String tipoEmissaoNormal = '1';

  /// Contingencia offline NFC-e (tpEmis 9).
  static const String tipoEmissaoContingenciaOfflineNfce = '9';
}

/// Forma de emissao na query string Focus (`forma_emissao=offline` para NFC-e).
enum FocusNfeFormaEmissaoUrl {
  normal,
  contingenciaOfflineNfce,
}

/// Opcoes de emissao (contingencia NFC-e apos falha de comunicacao SEFAZ).
class FocusNfeOpcoesEmissao {
  const FocusNfeOpcoesEmissao({
    this.forcarContingenciaOfflineNfce = false,
    this.tentarContingenciaSeFalhaComunicacao = true,
  });

  /// Emite ja em contingencia offline (URL `forma_emissao=offline`, tpEmis 9).
  final bool forcarContingenciaOfflineNfce;

  /// Se a Focus/SEFAZ falhar por timeout ou indisponibilidade, reenvia em contingencia.
  final bool tentarContingenciaSeFalhaComunicacao;
}

/// Credenciais e padroes fiscais injetados no servico.
class FocusNfeConfig {
  const FocusNfeConfig({
    required this.baseUrl,
    required this.apiToken,
    required this.cnpjEmitente,
    this.inscricaoEstadualEmitente = '',
    this.regimeTributarioEmitente = FiscalConfig.regimeTributarioEmitente,
    this.ambiente = FocusNfeAmbiente.homologacao,
    this.naturezaOperacaoNfce = FiscalConfig.naturezaOperacaoPadrao,
    this.naturezaOperacaoNfe = FiscalConfig.naturezaOperacaoPadrao,
    this.ncmPadrao = '44182000',
    this.cfopPadraoVendaInterna = '5102',
    this.ufEmitente = FiscalConfig.ufEmitente,
    this.icmsSituacaoTributariaPadrao =
        FiscalConfig.icmsSituacaoTributariaPadrao,
    this.icmsOrigemPadrao = FiscalConfig.icmsOrigemPadrao,
    this.pisCofinsSituacaoPadrao =
        FiscalConfig.pisCofinsSituacaoTributariaPadrao,
  });

  /// Ex.: `https://homologacao.focusnfe.com.br` ou `https://api.focusnfe.com.br`.
  final String baseUrl;

  /// Token do painel Focus (autenticacao HTTP Basic: `token:`).
  final String apiToken;

  /// CNPJ emitente (14 digitos).
  final String cnpjEmitente;

  /// IE do emitente (somente numeros).
  final String inscricaoEstadualEmitente;

  /// Regime tributario Focus (3 = Regime Normal / Lucro Presumido ou Real).
  final int regimeTributarioEmitente;

  final FocusNfeAmbiente ambiente;
  final String naturezaOperacaoNfce;
  final String naturezaOperacaoNfe;

  /// NCM padrao (materiais de construcao) quando o produto nao tiver NCM cadastrado.
  final String ncmPadrao;

  /// CFOP padrao venda dentro do estado (ex.: 5102).
  final String cfopPadraoVendaInterna;

  final String ufEmitente;
  final String icmsSituacaoTributariaPadrao;
  final String icmsOrigemPadrao;
  final String pisCofinsSituacaoPadrao;

  static const String baseUrlHomologacao =
      'https://homologacao.focusnfe.com.br';
  static const String baseUrlProducao = 'https://api.focusnfe.com.br';

  factory FocusNfeConfig.homologacao({
    required String apiToken,
    required String cnpjEmitente,
    String inscricaoEstadualEmitente = '',
    int regimeTributarioEmitente = FiscalConfig.regimeTributarioEmitente,
    String? naturezaOperacaoNfce,
    String? naturezaOperacaoNfe,
    String? ncmPadrao,
    String? cfopPadraoVendaInterna,
  }) {
    return FocusNfeConfig(
      baseUrl: baseUrlHomologacao,
      apiToken: apiToken,
      cnpjEmitente: cnpjEmitente,
      inscricaoEstadualEmitente: inscricaoEstadualEmitente,
      regimeTributarioEmitente: regimeTributarioEmitente,
      ambiente: FocusNfeAmbiente.homologacao,
      naturezaOperacaoNfce:
          naturezaOperacaoNfce ?? FiscalConfig.naturezaOperacaoPadrao,
      naturezaOperacaoNfe:
          naturezaOperacaoNfe ?? FiscalConfig.naturezaOperacaoPadrao,
      ncmPadrao: ncmPadrao ?? '44182000',
      cfopPadraoVendaInterna: cfopPadraoVendaInterna ?? '5102',
    );
  }

  factory FocusNfeConfig.producao({
    required String apiToken,
    required String cnpjEmitente,
    String inscricaoEstadualEmitente = '',
    int regimeTributarioEmitente = FiscalConfig.regimeTributarioEmitente,
    String? naturezaOperacaoNfce,
    String? naturezaOperacaoNfe,
    String? ncmPadrao,
    String? cfopPadraoVendaInterna,
  }) {
    return FocusNfeConfig(
      baseUrl: baseUrlProducao,
      apiToken: apiToken,
      cnpjEmitente: cnpjEmitente,
      inscricaoEstadualEmitente: inscricaoEstadualEmitente,
      regimeTributarioEmitente: regimeTributarioEmitente,
      ambiente: FocusNfeAmbiente.producao,
      naturezaOperacaoNfce:
          naturezaOperacaoNfce ?? FiscalConfig.naturezaOperacaoPadrao,
      naturezaOperacaoNfe:
          naturezaOperacaoNfe ?? FiscalConfig.naturezaOperacaoPadrao,
      ncmPadrao: ncmPadrao ?? '44182000',
      cfopPadraoVendaInterna: cfopPadraoVendaInterna ?? '5102',
    );
  }

  bool get configurado =>
      baseUrl.trim().isNotEmpty &&
      apiToken.trim().isNotEmpty &&
      _somenteDigitos(cnpjEmitente).length == 14 &&
      _somenteDigitos(inscricaoEstadualEmitente).isNotEmpty;

  String endpointNfce(
    String referencia, {
    FocusNfeFormaEmissaoUrl formaEmissao = FocusNfeFormaEmissaoUrl.normal,
  }) =>
      _endpoint('nfce', referencia, formaEmissao: formaEmissao);

  String endpointNfe(String referencia) => _endpoint('nfe', referencia);

  String _endpoint(
    String recurso,
    String referencia, {
    FocusNfeFormaEmissaoUrl formaEmissao = FocusNfeFormaEmissaoUrl.normal,
  }) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final params = <String, String>{'ref': referencia.trim()};
    if (formaEmissao == FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce) {
      params['forma_emissao'] = 'offline';
    }
    return Uri.parse('$base/v2/$recurso').replace(queryParameters: params).toString();
  }

  static String _somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');
}

/// Frete e volumes para NF-e de carga (modelo 55).
class FocusNfeDadosLogistica {
  const FocusNfeDadosLogistica({
    this.modalidadeFrete = 0,
    this.placaVeiculo = '',
    this.volumes = 1,
    this.pesoBrutoKg = 0,
    this.especieVolumes = 'VOLUMES',
  });

  /// 0 = CIF (emitente/remetente) | 1 = FOB (destinatario).
  final int modalidadeFrete;
  final String placaVeiculo;
  final int volumes;
  final double pesoBrutoKg;
  final String especieVolumes;
}

/// Item para NF-e de devolucao (quantidade devolvida + preco da venda original).
class FocusNfeItemDevolucao {
  const FocusNfeItemDevolucao({
    required this.produto,
    required this.descricao,
    required this.quantidade,
    required this.valorUnitario,
    this.cfopOverride = '',
    this.icmsOrigem = '',
    this.icmsSituacaoTributaria = '',
    this.icmsBaseCalculo,
    this.icmsAliquota,
    this.icmsValor,
    this.icmsBaseCalculoSt,
    this.icmsAliquotaSt,
    this.icmsValorSt,
    this.ipiValor,
  });

  final Produto produto;
  final String descricao;
  final int quantidade;
  final double valorUnitario;

  /// CFOP do espelho da fabrica (vazio = resolver automatico).
  final String cfopOverride;
  final String icmsOrigem;
  final String icmsSituacaoTributaria;
  final double? icmsBaseCalculo;
  final double? icmsAliquota;
  final double? icmsValor;
  final double? icmsBaseCalculoSt;
  final double? icmsAliquotaSt;
  final double? icmsValorSt;
  final double? ipiValor;
}

/// Destinatario completo exigido para NF-e modelo 55 (carga / construtora).
class FocusNfeDestinatarioNfe {
  const FocusNfeDestinatarioNfe({
    required this.nome,
    required this.documento,
    required this.inscricaoEstadual,
    required this.indicadorInscricaoEstadual,
    required this.logradouro,
    required this.numero,
    required this.bairro,
    required this.municipio,
    required this.codigoMunicipioIbge,
    required this.uf,
    required this.cep,
    this.telefone = '',
    this.email = '',
    this.complemento = '',
  });

  final String nome;
  final String documento;
  final String inscricaoEstadual;
  final String indicadorInscricaoEstadual;
  final String logradouro;
  final String numero;
  final String bairro;
  final String municipio;
  final String codigoMunicipioIbge;
  final String uf;
  final String cep;
  final String telefone;
  final String email;
  final String complemento;

  /// Monta a partir do cadastro; [codigoMunicipioIbge] deve vir da tabela IBGE.
  factory FocusNfeDestinatarioNfe.fromCliente(
    Cliente cliente, {
    required String codigoMunicipioIbge,
    EnderecoCliente? enderecoOverride,
  }) {
    final doc = cliente.documento.replaceAll(RegExp(r'\D'), '');
    final end = enderecoOverride ?? cliente.enderecoPadraoEntrega();
    if (end == null) {
      throw FocusNfeValidacaoException(
        'Cliente "${cliente.nomeRazao}" sem endereco para NF-e.',
      );
    }
    final ie = cliente.inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
    return FocusNfeDestinatarioNfe(
      nome: cliente.nomeRazao.trim(),
      documento: doc,
      inscricaoEstadual: ie,
      indicadorInscricaoEstadual: _indicadorIeCliente(cliente),
      logradouro: end.endereco.trim(),
      numero: end.numero.trim().isEmpty ? 'S/N' : end.numero.trim(),
      bairro: end.bairro.trim(),
      municipio: end.cidade.trim(),
      codigoMunicipioIbge: codigoMunicipioIbge.replaceAll(RegExp(r'\D'), ''),
      uf: end.uf.trim().toUpperCase(),
      cep: end.cep.replaceAll(RegExp(r'\D'), ''),
      telefone: cliente.telefone.replaceAll(RegExp(r'\D'), ''),
      email: cliente.email.trim(),
      complemento: end.referencia.trim(),
    );
  }

  /// Destinatario = fornecedor (emitente da NF-e de compra importada).
  factory FocusNfeDestinatarioNfe.fromEmitenteNfe(EmitenteNfeTemporario emit) {
    final doc = emit.cnpj.replaceAll(RegExp(r'\D'), '');
    final ie = emit.inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
    final ibge = emit.codigoMunicipioIbge.replaceAll(RegExp(r'\D'), '');
    if (emit.logradouro.trim().isEmpty ||
        emit.bairro.trim().isEmpty ||
        emit.municipio.trim().isEmpty ||
        emit.uf.trim().length != 2 ||
        ibge.length != 7) {
      throw FocusNfeValidacaoException(
        'XML da NF-e de compra sem endereco completo do fornecedor '
        '(logradouro, bairro, municipio, UF e cMun IBGE).',
      );
    }
    return FocusNfeDestinatarioNfe(
      nome: emit.razaoSocial.trim().isNotEmpty
          ? emit.razaoSocial.trim()
          : emit.nomeFantasia.trim(),
      documento: doc,
      inscricaoEstadual: ie,
      indicadorInscricaoEstadual: ie.isNotEmpty ? '1' : '9',
      logradouro: emit.logradouro.trim(),
      numero: emit.numero.trim().isEmpty ? 'S/N' : emit.numero.trim(),
      bairro: emit.bairro.trim(),
      municipio: emit.municipio.trim(),
      codigoMunicipioIbge: ibge,
      uf: emit.uf.trim().toUpperCase(),
      cep: emit.cep.replaceAll(RegExp(r'\D'), ''),
      telefone: emit.telefone.replaceAll(RegExp(r'\D'), ''),
      email: emit.email.trim(),
      complemento: emit.complemento.trim(),
    );
  }

  void validar() {
    final doc = documento.replaceAll(RegExp(r'\D'), '');
    if (doc.length != 11 && doc.length != 14) {
      throw FocusNfeValidacaoException(
        'Documento do destinatario invalido (informe CPF ou CNPJ).',
      );
    }
    if (nome.trim().isEmpty) {
      throw FocusNfeValidacaoException('Nome do destinatario obrigatorio.');
    }
    if (logradouro.trim().isEmpty ||
        bairro.trim().isEmpty ||
        municipio.trim().isEmpty ||
        uf.trim().length != 2) {
      throw FocusNfeValidacaoException(
        'Endereco do destinatario incompleto para NF-e.',
      );
    }
    final ibge = codigoMunicipioIbge.replaceAll(RegExp(r'\D'), '');
    if (ibge.length != 7) {
      throw FocusNfeValidacaoException(
        'Codigo IBGE do municipio deve ter 7 digitos.',
      );
    }
    final cepDigits = cep.replaceAll(RegExp(r'\D'), '');
    if (cepDigits.length != 8) {
      throw FocusNfeValidacaoException('CEP do destinatario invalido.');
    }
    if (indicadorInscricaoEstadual == '1') {
      final ie = inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
      if (ie.isEmpty) {
        throw FocusNfeValidacaoException(
          'Inscricao Estadual obrigatoria para clientes contribuintes de ICMS.',
        );
      }
    }
  }
}

/// Resultado padronizado para gravar metadados na [Venda] (caixa / repositorio).
class FocusNfeEmissaoResultado {
  const FocusNfeEmissaoResultado({
    required this.autorizada,
    required this.rejeitada,
    required this.processando,
    this.statusFocus = '',
    this.statusSefaz = '',
    this.chaveNfe = '',
    this.numero = '',
    this.serie = '',
    this.protocolo = '',
    this.urlDanfe = '',
    this.urlXml = '',
    this.urlXmlCancelamento = '',
    this.mensagem = '',
    this.referencia = '',
    this.httpStatusCode = 0,
    this.payloadBruto,
  });

  final bool autorizada;
  final bool rejeitada;
  final bool processando;
  final String statusFocus;
  final String statusSefaz;
  final String chaveNfe;
  final String numero;
  final String serie;
  final String protocolo;
  final String urlDanfe;
  final String urlXml;
  final String urlXmlCancelamento;
  final String mensagem;

  bool get cancelada =>
      statusFocus == 'cancelado' ||
      statusSefaz == '135' ||
      statusSefaz == '101';
  final String referencia;
  final int httpStatusCode;
  final Map<String, dynamic>? payloadBruto;

  bool get sucesso => autorizada;

  factory FocusNfeEmissaoResultado.erro(
    String mensagem, {
    int httpStatusCode = 0,
    Map<String, dynamic>? payloadBruto,
  }) {
    return FocusNfeEmissaoResultado(
      autorizada: false,
      rejeitada: true,
      processando: false,
      mensagem: mensagem,
      httpStatusCode: httpStatusCode,
      payloadBruto: payloadBruto,
    );
  }

  factory FocusNfeEmissaoResultado.deRespostaFocus(
    Map<String, dynamic> json, {
    required String referencia,
    int httpStatusCode = 200,
    String apiBaseUrl = '',
  }) {
    final status = (json['status'] ?? '').toString().trim().toLowerCase();
    final statusSefaz = (json['status_sefaz'] ?? '').toString();
    final mensagemSefaz = (json['mensagem_sefaz'] ?? '').toString();
    final mensagemApi = (json['mensagem'] ?? json['message'] ?? '').toString();
    final chave = (json['chave_nfe'] ?? json['chave_acesso'] ?? '').toString();
    final urlDanfe = FocusDocumentoFiscalUrl.normalizar(
      (json['caminho_danfe'] ??
              json['url_danfe'] ??
              json['danfe'] ??
              json['url_pdf'] ??
              '')
          .toString(),
      apiBaseUrl: apiBaseUrl,
    );
    final urlXml = FocusDocumentoFiscalUrl.normalizar(
      (json['caminho_xml_nota_fiscal'] ??
              json['caminho_xml'] ??
              json['url_xml'] ??
              '')
          .toString(),
      apiBaseUrl: apiBaseUrl,
    );
    final urlXmlCancelamento = FocusDocumentoFiscalUrl.normalizar(
      (json['caminho_xml_cancelamento'] ??
              json['url_xml_cancelamento'] ??
              json['caminho_xml_evento_cancelamento'] ??
              '')
          .toString(),
      apiBaseUrl: apiBaseUrl,
    );

    final cancelada =
        status == 'cancelado' || statusSefaz == '135' || statusSefaz == '101';
    final autorizada = !cancelada &&
        (status == 'autorizado' ||
            (statusSefaz == '100' && chave.isNotEmpty));
    final processando = status == 'processando_autorizacao';
    final rejeitada = !autorizada &&
        !cancelada &&
        !processando &&
        (status == 'erro_autorizacao' ||
            status == 'denegado' ||
            statusSefaz.isNotEmpty && statusSefaz != '100' ||
            mensagemSefaz.isNotEmpty);

    var msg = mensagemSefaz.trim();
    if (msg.isEmpty) msg = mensagemApi.trim();
    if (msg.isEmpty && rejeitada) {
      msg = 'Nota rejeitada pela SEFAZ (status: $status).';
    }
    if (msg.isEmpty && cancelada) {
      msg = 'Nota cancelada.';
    }
    if (msg.isEmpty && autorizada) {
      msg = 'Nota autorizada.';
    }

    return FocusNfeEmissaoResultado(
      autorizada: autorizada,
      rejeitada: rejeitada && !processando,
      processando: processando,
      statusFocus: status,
      statusSefaz: statusSefaz,
      chaveNfe: chave,
      numero: (json['numero'] ?? '').toString(),
      serie: (json['serie'] ?? '').toString(),
      protocolo: (json['protocolo'] ?? json['protocolo_nfe'] ?? '').toString(),
      urlDanfe: urlDanfe,
      urlXml: urlXml,
      urlXmlCancelamento: urlXmlCancelamento,
      mensagem: msg,
      referencia: referencia,
      httpStatusCode: httpStatusCode,
      payloadBruto: json,
    );
  }
}

/// Resultado da emissao de Carta de Correcao (CC-e).
class FocusNfeCartaCorrecaoResultado {
  const FocusNfeCartaCorrecaoResultado({
    required this.sucesso,
    this.mensagem = '',
    this.numeroSequencia = 0,
    this.urlPdf = '',
    this.urlXml = '',
    this.protocolo = '',
    this.statusFocus = '',
    this.processando = false,
  });

  final bool sucesso;
  final String mensagem;
  final int numeroSequencia;
  final String urlPdf;
  final String urlXml;
  final String protocolo;
  final String statusFocus;
  final bool processando;

  factory FocusNfeCartaCorrecaoResultado.erro(String mensagem) {
    return FocusNfeCartaCorrecaoResultado(sucesso: false, mensagem: mensagem);
  }
}

/// Resultado de operacao auxiliar (e-mail, inutilizacao).
class FocusNfeOperacaoSimplesResultado {
  const FocusNfeOperacaoSimplesResultado({
    required this.sucesso,
    this.mensagem = '',
    this.httpStatusCode = 0,
    this.protocolo = '',
    this.urlXml = '',
    this.xmlCorpo = '',
  });

  final bool sucesso;
  final String mensagem;
  final int httpStatusCode;
  final String protocolo;
  final String urlXml;
  final String xmlCorpo;

  factory FocusNfeOperacaoSimplesResultado.erro(String mensagem) {
    return FocusNfeOperacaoSimplesResultado(sucesso: false, mensagem: mensagem);
  }
}

/// Resultado da pre-visualizacao DANFe (POST /v2/nfe/danfe).
class FocusNfePreviaDanfeResultado {
  const FocusNfePreviaDanfeResultado({
    this.pdfBytes,
    this.html,
    this.mensagemErro = '',
    this.httpStatusCode = 0,
  });

  final Uint8List? pdfBytes;
  final String? html;
  final String mensagemErro;
  final int httpStatusCode;

  bool get sucesso =>
      (pdfBytes != null && pdfBytes!.isNotEmpty) ||
      (html != null && html!.trim().isNotEmpty);
}

/// Integracao HTTP com a API Focus NFe (NFC-e modelo 65 e NF-e modelo 55).
class FocusNfeService {
  FocusNfeService({
    required FocusNfeConfig config,
    http.Client? httpClient,
    FiscalService? fiscalService,
  })  : _config = config,
        _http = httpClient ?? http.Client(),
        _fiscal = fiscalService ?? FiscalService(httpClient: httpClient);

  final FocusNfeConfig _config;
  final http.Client _http;
  final FiscalService _fiscal;

  FocusNfeConfig get config => _config;

  static final DateFormat _isoEmissao = DateFormat("yyyy-MM-dd'T'HH:mm:ssXXX");
  static final DateFormat _isoEmissaoSemFuso =
      DateFormat("yyyy-MM-dd'T'HH:mm:ss");

  /// Fuso fixo Brasil (sem horario de verao desde 2019).
  static const String _offsetFiscalBrasil = '-03:00';

  /// Margem para evitar rejeicao SEFAZ "data-hora posterior ao recebimento".
  static const Duration _margemDataEmissaoNfce = Duration(seconds: 45);

  static const String _justificativaContingenciaNfcePadrao =
      'Indisponibilidade de comunicacao com a SEFAZ para autorizacao da NFC-e.';

  /// Horario de emissao para Focus/SEFAZ: relogio local do PC + offset Brasil fixo.
  ///
  /// Evita rejeicao quando o Windows exibe a hora certa mas o fuso automatico
  /// esta errado (ex.: UTC em vez de Brasilia).
  @visibleForTesting
  static String dataEmissaoFocus({
    DateTime? base,
    bool margemSeguranca = false,
    String offset = _offsetFiscalBrasil,
  }) {
    final local = base ?? DateTime.now();
    var dt = DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
    if (margemSeguranca) {
      dt = dt.subtract(_margemDataEmissaoNfce);
    }
    return '${_isoEmissaoSemFuso.format(dt)}$offset';
  }

  void validarConfiguracao() {
    if (!_config.configurado) {
      throw FocusNfeConfigIncompletaException(
        'Focus NFe nao configurado neste computador. '
        'Abra Configuracoes → Fiscal — Focus NFe, informe o token da API, '
        'CNPJ, inscricao estadual e o ambiente (homologacao ou producao), '
        'depois salve e tente emitir novamente.',
      );
    }
  }

  /// Emite NFC-e (modelo 65) para venda finalizada no caixa.
  ///
  /// [opcoes.forcarContingenciaOfflineNfce] ou falha de comunicacao SEFAZ/Focus
  /// disparam reenvio com `forma_emissao=offline` e `tipo_emissao` 9.
  Future<FocusNfeEmissaoResultado> emitirNfce(
    Venda venda, {
    Cliente? cliente,
    String? referencia,
    String ufDestino = FiscalConfig.ufEmitente,
    bool entregaDomicilio = false,
    FocusNfeOpcoesEmissao opcoes = const FocusNfeOpcoesEmissao(),
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) async {
    validarConfiguracao();
    final bloqueioNfce = VendaDocumentoFiscalMutex.mensagemBloqueioNovaNfce(venda);
    if (bloqueioNfce != null) {
      return FocusNfeEmissaoResultado.erro(bloqueioNfce);
    }
    final ref = referencia ?? referenciaVendaNfce(venda);
    final contingencia = opcoes.forcarContingenciaOfflineNfce;
    final formaUrl = contingencia
        ? FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce
        : FocusNfeFormaEmissaoUrl.normal;
    final tipoEmissao = contingencia
        ? FocusNfeEmissaoSefaz.tipoEmissaoContingenciaOfflineNfce
        : FocusNfeEmissaoSefaz.tipoEmissaoNormal;

    final emissaoBase = DateTime.now();
    var payload = montarPayloadNfce(
      venda,
      cliente: cliente,
      ufDestino: ufDestino,
      entregaDomicilio: entregaDomicilio,
      tipoEmissao: tipoEmissao,
      formaEmissao: formaUrl,
      dataEmissao: emissaoBase,
      itens: itens,
      obterProduto: obterProduto,
    );
    var resultado = await _postDocumento(
      uri: Uri.parse(_config.endpointNfce(ref, formaEmissao: formaUrl)),
      payload: payload,
      referencia: ref,
    );

    if (!contingencia &&
        opcoes.tentarContingenciaSeFalhaComunicacao &&
        _deveTentarContingenciaNfce(resultado)) {
      payload = montarPayloadNfce(
        venda,
        cliente: cliente,
        ufDestino: ufDestino,
        entregaDomicilio: entregaDomicilio,
        tipoEmissao: FocusNfeEmissaoSefaz.tipoEmissaoContingenciaOfflineNfce,
        formaEmissao: FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce,
        dataEmissao: DateTime.now(),
        itens: itens,
        obterProduto: obterProduto,
      );
      resultado = await _postDocumento(
        uri: Uri.parse(
          _config.endpointNfce(
            ref,
            formaEmissao: FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce,
          ),
        ),
        payload: payload,
        referencia: ref,
        contingenciaOffline: true,
      );
    }

    return resultado;
  }

  /// Emite NF-e (modelo 55) — exige destinatario completo com IBGE.
  Future<FocusNfeEmissaoResultado> emitirNfe(
    Venda venda, {
    required FocusNfeDestinatarioNfe destinatario,
    String? referencia,
    FocusNfeDadosLogistica? logistica,
  }) async {
    validarConfiguracao();
    final ref = referencia ?? referenciaVendaNfe(venda);
    final payload = montarPayloadNfe(
      venda,
      destinatario: destinatario,
      logistica: logistica,
    );
    return _postDocumento(
      uri: Uri.parse(_config.endpointNfe(ref)),
      payload: payload,
      referencia: ref,
    );
  }

  /// Consulta status de NF-e ja enviada (reconsulta / contingencia).
  Future<FocusNfeEmissaoResultado> consultarNfe(String referencia) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeEmissaoResultado.erro('Referencia da NF-e invalida.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v2/nfe/${Uri.encodeComponent(ref)}');
    try {
      final response = await _http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 60));
      Map<String, dynamic>? jsonBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        } else if (decoded is Map) {
          jsonBody = decoded.cast<String, dynamic>();
        }
      } catch (_) {}
      if (jsonBody == null) {
        return FocusNfeEmissaoResultado.erro(
          'Resposta invalida ao consultar NF-e.',
          httpStatusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FocusNfeEmissaoResultado.erro(
          _extrairMensagemErroApi(jsonBody, jsonBody['erros']),
          httpStatusCode: response.statusCode,
          payloadBruto: jsonBody,
        );
      }
      return FocusNfeEmissaoResultado.deRespostaFocus(
        jsonBody,
        referencia: ref,
        httpStatusCode: response.statusCode,
        apiBaseUrl: _config.baseUrl,
      );
    } catch (e) {
      return FocusNfeEmissaoResultado.erro('Falha ao consultar NF-e na Focus: $e');
    }
  }

  /// Cancela NF-e autorizada (DELETE /v2/nfe/{referencia}).
  Future<FocusNfeEmissaoResultado> cancelarNfe(
    String referencia, {
    required String justificativa,
  }) async {
    return _cancelarDocumentoFocus(
      segmento: 'nfe',
      referencia: referencia,
      justificativa: justificativa,
      rotulo: 'NF-e',
    );
  }

  /// Cancela NFC-e autorizada (DELETE /v2/nfce/{referencia}).
  Future<FocusNfeEmissaoResultado> cancelarNfce(
    String referencia, {
    required String justificativa,
  }) async {
    return _cancelarDocumentoFocus(
      segmento: 'nfce',
      referencia: referencia,
      justificativa: justificativa,
      rotulo: 'NFC-e',
    );
  }

  Future<FocusNfeEmissaoResultado> _cancelarDocumentoFocus({
    required String segmento,
    required String referencia,
    required String justificativa,
    required String rotulo,
  }) async {
    validarConfiguracao();
    final just = justificativa.trim();
    if (just.length < 15 || just.length > 255) {
      return FocusNfeEmissaoResultado.erro(
        'Justificativa do cancelamento deve ter entre 15 e 255 caracteres.',
      );
    }
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeEmissaoResultado.erro('Referencia da $rotulo invalida.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v2/$segmento/${Uri.encodeComponent(ref)}');
    try {
      final request = http.Request('DELETE', uri)
        ..headers.addAll(_headers())
        ..body = jsonEncode({'justificativa': just});
      final streamed = await _http.send(request).timeout(
        const Duration(seconds: 90),
      );
      final response = await http.Response.fromStream(streamed);
      return _interpretarRespostaJsonHttp(response, referencia: ref);
    } catch (e) {
      return FocusNfeEmissaoResultado.erro(
        'Falha ao cancelar $rotulo na Focus: $e',
      );
    }
  }

  /// Envia NF-e por e-mail (POST /v2/nfe/{referencia}/email).
  Future<FocusNfeOperacaoSimplesResultado> enviarEmailNfe(
    String referencia, {
    required List<String> emails,
  }) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeOperacaoSimplesResultado.erro('Referencia da NF-e invalida.');
    }
    final lista = emails
        .map((e) => e.trim())
        .where((e) => e.contains('@') && e.length >= 5)
        .take(10)
        .toList();
    if (lista.isEmpty) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Informe ao menos um e-mail valido (maximo 10).',
      );
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/v2/nfe/${Uri.encodeComponent(ref)}/email',
    );
    try {
      final response = await _http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode({'emails': lista}),
          )
          .timeout(const Duration(seconds: 60));
      return _interpretarOperacaoSimples(response);
    } catch (e) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Falha ao enviar e-mail da NF-e: $e',
      );
    }
  }

  /// Inutiliza faixa de numeracao NF-e (POST /v2/nfe/inutilizacao).
  Future<FocusNfeOperacaoSimplesResultado> inutilizarNumeracaoNfe({
    String? cnpjEmitente,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
  }) =>
      _inutilizarNumeracao(
        path: '/v2/nfe/inutilizacao',
        rotulo: 'NF-e',
        cnpjEmitente: cnpjEmitente,
        serie: serie,
        numeroInicial: numeroInicial,
        numeroFinal: numeroFinal,
        justificativa: justificativa,
      );

  /// Inutiliza faixa de numeracao NFC-e (POST /v2/nfce/inutilizacao).
  Future<FocusNfeOperacaoSimplesResultado> inutilizarNumeracaoNfce({
    String? cnpjEmitente,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
  }) =>
      _inutilizarNumeracao(
        path: '/v2/nfce/inutilizacao',
        rotulo: 'NFC-e',
        cnpjEmitente: cnpjEmitente,
        serie: serie,
        numeroInicial: numeroInicial,
        numeroFinal: numeroFinal,
        justificativa: justificativa,
      );

  Future<FocusNfeOperacaoSimplesResultado> _inutilizarNumeracao({
    required String path,
    required String rotulo,
    String? cnpjEmitente,
    required String serie,
    required int numeroInicial,
    required int numeroFinal,
    required String justificativa,
  }) async {
    validarConfiguracao();
    final just = justificativa.trim();
    if (just.length < 15 || just.length > 255) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Justificativa deve ter entre 15 e 255 caracteres.',
      );
    }
    if (numeroInicial <= 0 || numeroFinal < numeroInicial) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Faixa de numeros invalida (inicial <= final, ambos > 0).',
      );
    }
    if (numeroFinal - numeroInicial > 9999) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Faixa maxima de 10.000 numeros por pedido (SEFAZ).',
      );
    }
    final cnpj = (cnpjEmitente ?? _config.cnpjEmitente)
        .replaceAll(RegExp(r'\D'), '');
    if (cnpj.length != 14) {
      return FocusNfeOperacaoSimplesResultado.erro('CNPJ emitente invalido.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    final body = <String, dynamic>{
      'cnpj': cnpj,
      'serie': serie.trim().isNotEmpty ? serie.trim() : '1',
      'numero_inicial': numeroInicial.toString(),
      'numero_final': numeroFinal.toString(),
      'justificativa': just,
    };
    try {
      final response = await _http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      return _interpretarOperacaoSimples(response);
    } catch (e) {
      return FocusNfeOperacaoSimplesResultado.erro(
        'Falha ao inutilizar numeracao $rotulo na Focus: $e',
      );
    }
  }

  /// Consulta CC-e ja enviada (GET /v2/nfe/{referencia}/carta_correcao).
  Future<FocusNfeCartaCorrecaoResultado> consultarCartaCorrecaoNfe(
    String referencia, {
    int? numeroSequencia,
  }) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeCartaCorrecaoResultado.erro('Referencia da NF-e invalida.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    var uri = Uri.parse(
      '$base/v2/nfe/${Uri.encodeComponent(ref)}/carta_correcao',
    );
    if (numeroSequencia != null && numeroSequencia > 0) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'numero_sequencial': numeroSequencia.toString(),
        },
      );
    }
    try {
      final response = await _http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 60));
      return _interpretarCartaCorrecao(response, referencia: ref);
    } catch (e) {
      return FocusNfeCartaCorrecaoResultado.erro(
        'Falha ao consultar CC-e na Focus: $e',
      );
    }
  }

  /// Carta de Correcao Eletronica (CC-e) — POST /v2/nfe/{referencia}/carta_correcao.
  Future<FocusNfeCartaCorrecaoResultado> emitirCartaCorrecaoNfe(
    String referencia, {
    required String correcao,
    String? condicoesUso,
  }) async {
    validarConfiguracao();
    final texto = correcao.trim();
    if (texto.length < 15) {
      return FocusNfeCartaCorrecaoResultado.erro(
        'Texto da correcao deve ter pelo menos 15 caracteres.',
      );
    }
    if (texto.length > 1000) {
      return FocusNfeCartaCorrecaoResultado.erro(
        'Texto da correcao deve ter no maximo 1000 caracteres (SEFAZ).',
      );
    }
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeCartaCorrecaoResultado.erro('Referencia da NF-e invalida.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/v2/nfe/${Uri.encodeComponent(ref)}/carta_correcao',
    );
    final body = <String, dynamic>{'correcao': texto};
    final cond = (condicoesUso ?? '').trim();
    if (cond.isNotEmpty) body['condicoes_uso'] = cond;

    try {
      final response = await _http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      return _interpretarCartaCorrecao(response, referencia: ref);
    } catch (e) {
      return FocusNfeCartaCorrecaoResultado.erro(
        'Falha ao emitir carta de correcao: $e',
      );
    }
  }

  FocusNfeOperacaoSimplesResultado _interpretarOperacaoSimples(
    http.Response response,
  ) {
    Map<String, dynamic>? jsonBody;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        jsonBody = decoded;
      } else if (decoded is Map) {
        jsonBody = decoded.cast<String, dynamic>();
      }
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final corpo = response.body.trim();
      final corpoXml = corpo.startsWith('<') ? corpo : '';
      final msg = jsonBody == null
          ? ''
          : (jsonBody['mensagem'] ?? jsonBody['status'] ?? '').toString().trim();
      final protocolo = jsonBody == null
          ? ''
          : (jsonBody['protocolo'] ??
                  jsonBody['numero_protocolo'] ??
                  jsonBody['protocolo_sefaz'] ??
                  '')
              .toString()
              .trim();
      final urlXml = jsonBody == null
          ? ''
          : (jsonBody['caminho_xml_nota_fiscal'] ??
                  jsonBody['caminho_xml'] ??
                  jsonBody['url_xml'] ??
                  jsonBody['caminho_xml_evento'] ??
                  '')
              .toString()
              .trim();
      return FocusNfeOperacaoSimplesResultado(
        sucesso: true,
        mensagem: msg.isNotEmpty ? msg : 'Operacao concluida.',
        httpStatusCode: response.statusCode,
        protocolo: protocolo,
        urlXml: urlXml,
        xmlCorpo: corpoXml,
      );
    }
    final msg = jsonBody != null
        ? _extrairMensagemErroApi(jsonBody, jsonBody['erros'])
        : 'HTTP ${response.statusCode}';
    return FocusNfeOperacaoSimplesResultado(
      sucesso: false,
      mensagem: msg,
      httpStatusCode: response.statusCode,
    );
  }

  FocusNfeEmissaoResultado _interpretarRespostaJsonHttp(
    http.Response response, {
    required String referencia,
  }) {
    Map<String, dynamic>? jsonBody;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        jsonBody = decoded;
      } else if (decoded is Map) {
        jsonBody = decoded.cast<String, dynamic>();
      }
    } catch (_) {}

    if (jsonBody == null) {
      return FocusNfeEmissaoResultado.erro(
        'Resposta invalida da Focus (HTTP ${response.statusCode}).',
        httpStatusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return FocusNfeEmissaoResultado.erro(
        _extrairMensagemErroApi(jsonBody, jsonBody['erros']),
        httpStatusCode: response.statusCode,
        payloadBruto: jsonBody,
      );
    }
    return FocusNfeEmissaoResultado.deRespostaFocus(
      jsonBody,
      referencia: referencia,
      httpStatusCode: response.statusCode,
      apiBaseUrl: _config.baseUrl,
    );
  }

  FocusNfeCartaCorrecaoResultado _interpretarCartaCorrecao(
    http.Response response, {
    required String referencia,
  }) {
    Map<String, dynamic>? jsonBody;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        jsonBody = decoded;
      } else if (decoded is Map) {
        jsonBody = decoded.cast<String, dynamic>();
      }
    } catch (_) {}

    if (jsonBody == null) {
      return FocusNfeCartaCorrecaoResultado.erro(
        'Resposta invalida da Focus (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return FocusNfeCartaCorrecaoResultado.erro(
        _extrairMensagemErroApi(jsonBody, jsonBody['erros']),
      );
    }

    final numero = ((jsonBody['numero_carta_correcao'] as num?) ?? 0).toInt();
    final pdf = (jsonBody['caminho_pdf_carta_correcao'] ??
            jsonBody['url_pdf_carta_correcao'] ??
            '')
        .toString()
        .trim();
    final xml = (jsonBody['caminho_xml_carta_correcao'] ??
            jsonBody['url_xml_carta_correcao'] ??
            '')
        .toString()
        .trim();
    final msg = (jsonBody['mensagem_sefaz'] ?? jsonBody['mensagem'] ?? '')
        .toString()
        .trim();
    final protocolo = (jsonBody['protocolo'] ??
            jsonBody['numero_protocolo'] ??
            jsonBody['protocolo_sefaz'] ??
            '')
        .toString()
        .trim();
    final statusFocus = (jsonBody['status'] ?? jsonBody['status_sefaz'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final processando = statusFocus.contains('processando') && xml.isEmpty;

    return FocusNfeCartaCorrecaoResultado(
      sucesso: true,
      mensagem: msg.isEmpty
          ? (processando
              ? 'CC-e em processamento na SEFAZ.'
              : 'Carta de correcao registrada.')
          : msg,
      numeroSequencia: numero > 0 ? numero : 1,
      urlPdf: pdf,
      urlXml: xml,
      protocolo: protocolo,
      statusFocus: statusFocus.isEmpty ? 'autorizado' : statusFocus,
      processando: processando,
    );
  }

  /// Gera DANFe de pre-visualizacao (nao transmite a SEFAZ).
  ///
  /// POST `{baseUrl}/v2/nfe/danfe` com o mesmo JSON da emissao.
  Future<FocusNfePreviaDanfeResultado> previsualizarDanfeNfe(
    Map<String, dynamic> payload, {
    bool preferirHtml = false,
  }) async {
    validarConfiguracao();
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v2/nfe/danfe');
    final accept = preferirHtml ? 'text/html' : 'application/pdf';

    try {
      final response = await _http
          .post(
            uri,
            headers: {
              ..._headers(),
              'Accept': accept,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (contentType.contains('pdf') ||
            _parecePdf(response.bodyBytes)) {
          return FocusNfePreviaDanfeResultado(
            pdfBytes: Uint8List.fromList(response.bodyBytes),
            httpStatusCode: response.statusCode,
          );
        }
        if (contentType.contains('html') || preferirHtml) {
          return FocusNfePreviaDanfeResultado(
            html: response.body,
            httpStatusCode: response.statusCode,
          );
        }
        return FocusNfePreviaDanfeResultado(
          pdfBytes: Uint8List.fromList(response.bodyBytes),
          httpStatusCode: response.statusCode,
        );
      }

      Map<String, dynamic>? jsonBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        } else if (decoded is Map) {
          jsonBody = decoded.cast<String, dynamic>();
        }
      } catch (_) {}

      final msg = jsonBody != null
          ? _extrairMensagemErroApi(jsonBody, jsonBody['erros'])
          : 'Falha na pre-visualizacao DANFe (HTTP ${response.statusCode}).';

      return FocusNfePreviaDanfeResultado(
        mensagemErro: msg,
        httpStatusCode: response.statusCode,
      );
    } catch (e) {
      return FocusNfePreviaDanfeResultado(
        mensagemErro: 'Falha ao gerar DANFe de pre-visualizacao: $e',
      );
    }
  }

  static bool _parecePdf(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  /// Baixa PDF do DANFE (requer token Focus na maioria dos endpoints).
  Future<Uint8List?> baixarDocumentoPdf(Uri uri) async {
    validarConfiguracao();
    try {
      final response = await _http
          .get(
            uri,
            headers: {
              ..._headers(),
              'Accept': 'application/pdf',
            },
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          _parecePdf(response.bodyBytes)) {
        return Uint8List.fromList(response.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  /// Baixa XML fiscal (inutilizacao, eventos) com autenticacao Focus.
  Future<String?> baixarDocumentoXml(String url) async {
    validarConfiguracao();
    final normalizada = FocusDocumentoFiscalUrl.normalizar(
      url,
      apiBaseUrl: _config.baseUrl,
    );
    if (normalizada.isEmpty) return null;
    try {
      final response = await _http
          .get(
            Uri.parse(normalizada),
            headers: {
              ..._headers(),
              'Accept': 'application/xml, text/xml, */*',
            },
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = utf8.decode(response.bodyBytes);
      return body.trim().startsWith('<') ? body : null;
    } catch (_) {}
    return null;
  }

  /// Consulta NFC-e ja enviada (URL do XML / reconsulta SEFAZ).
  Future<FocusNfeEmissaoResultado> consultarNfce(String referencia) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeEmissaoResultado.erro('Referencia da NFC-e invalida.');
    }
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v2/nfce/${Uri.encodeComponent(ref)}');
    try {
      final response = await _http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 60));
      Map<String, dynamic>? jsonBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        } else if (decoded is Map) {
          jsonBody = decoded.cast<String, dynamic>();
        }
      } catch (_) {}
      if (jsonBody == null) {
        return FocusNfeEmissaoResultado.erro(
          'Resposta invalida ao consultar NFC-e.',
          httpStatusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FocusNfeEmissaoResultado.erro(
          _extrairMensagemErroApi(jsonBody, jsonBody['erros']),
          httpStatusCode: response.statusCode,
          payloadBruto: jsonBody,
        );
      }
      return FocusNfeEmissaoResultado.deRespostaFocus(
        jsonBody,
        referencia: ref,
        httpStatusCode: response.statusCode,
        apiBaseUrl: _config.baseUrl,
      );
    } catch (e) {
      return FocusNfeEmissaoResultado.erro('Falha ao consultar NFC-e na Focus: $e');
    }
  }

  /// Monta JSON NFC-e (Focus API v2) a partir da venda.
  ///
  /// Itens incluem tributacao Regime Normal via [_tributacaoItemPadrao]
  /// (ICMS CST 00, PIS/COFINS 01 por padrao no balcao).
  /// Referencia Focus estavel por venda (reemissao = mesma URL `ref`).
  static String referenciaVendaNfce(Venda venda) => _referenciaVenda(venda, 'nfce');

  static String referenciaVendaNfe(Venda venda) => _referenciaVenda(venda, 'nfe');

  Map<String, dynamic> montarPayloadNfce(
    Venda venda, {
    Cliente? cliente,
    String ufDestino = FiscalConfig.ufEmitente,
    bool entregaDomicilio = false,
    String tipoEmissao = FocusNfeEmissaoSefaz.tipoEmissaoNormal,
    FocusNfeFormaEmissaoUrl formaEmissao = FocusNfeFormaEmissaoUrl.normal,
    DateTime? dataEmissao,
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    final itensPayload = _itensFocusDeVenda(
      venda,
      ufDestino: ufDestino,
      itens: itens,
      obterProduto: obterProduto,
    );
    if (itensPayload.isEmpty) {
      throw FocusNfeValidacaoException('Venda sem itens para NFC-e.');
    }

    final valorProdutos = _somaValorBrutoItens(itensPayload);
    final desconto = venda.descontoImplicitoTotal;
    final frete = venda.valorFrete;
    final valorTotal = (valorProdutos + frete - desconto)
        .clamp(0, double.infinity)
        .toDouble();

    final docDest = _documentoDestinatario(cliente);
    final contingenciaOffline =
        tipoEmissao == FocusNfeEmissaoSefaz.tipoEmissaoContingenciaOfflineNfce;
    final dataEmissaoIso = dataEmissaoFocus(
      base: dataEmissao,
      margemSeguranca: true,
    );
    final payload = <String, dynamic>{
      ..._camposEmitenteFocus(),
      ..._camposTipoEmissao(
        tipoEmissao: tipoEmissao,
        formaEmissao: formaEmissao,
        incluirFormaEmissaoNoCorpo: true,
      ),
      'natureza_operacao': _config.naturezaOperacaoNfce,
      'data_emissao': dataEmissaoIso,
      'tipo_documento': '1',
      'local_destino': _localDestino(ufDestino),
      'finalidade_emissao': '1',
      'consumidor_final': '1',
      'presenca_comprador': entregaDomicilio ? '4' : '1',
      'modalidade_frete': '9',
      'valor_produtos': _formatarDecimal(valorProdutos),
      'valor_desconto': _formatarDecimal(desconto),
      'valor_frete': _formatarDecimal(frete),
      'valor_total': _formatarDecimal(valorTotal),
      'items': itensPayload,
      'formas_pagamento': _formasPagamentoDeVenda(venda, valorTotal),
      'informacoes_adicionais_contribuinte': _observacaoVenda(venda),
    };

    if (contingenciaOffline) {
      payload['data_entrada_contingencia'] = dataEmissaoIso;
      payload['motivo_entrada_contingencia'] =
          _justificativaContingenciaNfcePadrao;
    }

    if (docDest != null) {
      if (docDest.length == 11) {
        payload['cpf_destinatario'] = docDest;
      } else if (docDest.length == 14) {
        payload['cnpj_destinatario'] = docDest;
      }
      final nome = cliente?.nomeRazao.trim() ?? '';
      if (nome.isNotEmpty) {
        payload['nome_destinatario'] = nome;
      }
      payload['indicador_inscricao_estadual_destinatario'] = '9';
    }

    return payload;
  }

  /// Monta JSON NF-e (modelo 55) para entrega / construtora.
  ///
  /// CFOP dinamico (UF destino + consumidor final), cobranca a prazo e GTIN.
  Map<String, dynamic> montarPayloadNfe(
    Venda venda, {
    required FocusNfeDestinatarioNfe destinatario,
    FocusNfeDadosLogistica? logistica,
    String tipoEmissao = FocusNfeEmissaoSefaz.tipoEmissaoNormal,
  }) {
    destinatario.validar();

    final ufDestino = destinatario.uf.trim().toUpperCase();
    final consumidorFinal = _consumidorFinalNfe(destinatario);

    final log = logistica ?? const FocusNfeDadosLogistica();
    final modalidadeFrete = log.modalidadeFrete.clamp(0, 9);
    final itens = _itensFocusDeVenda(
      venda,
      ufDestino: ufDestino,
      emissaoNfe: true,
      consumidorFinal: consumidorFinal,
    );
    if (itens.isEmpty) {
      throw FocusNfeValidacaoException('Venda sem itens para NF-e.');
    }

    final valorProdutos = _somaValorBrutoItens(itens);
    final desconto = venda.descontoImplicitoTotal;
    final frete = venda.valorFrete;
    final valorTotal = (valorProdutos + frete - desconto)
        .clamp(0, double.infinity)
        .toDouble();

    final doc = destinatario.documento.replaceAll(RegExp(r'\D'), '');
    final ieDest = destinatario.inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
    final payload = <String, dynamic>{
      ..._camposEmitenteFocus(),
      ..._camposTipoEmissao(tipoEmissao: tipoEmissao),
      'natureza_operacao': _config.naturezaOperacaoNfe,
      'data_emissao': _isoEmissao.format(DateTime.now()),
      'tipo_documento': '1',
      'local_destino': _localDestino(
        ufDestino,
        ufDestinatario: ufDestino,
      ),
      'finalidade_emissao': '1',
      'consumidor_final': consumidorFinal ? '1' : '0',
      'presenca_comprador': '1',
      'nome_destinatario': destinatario.nome,
      if (ieDest.isNotEmpty) 'inscricao_estadual_destinatario': ieDest,
      'indicador_inscricao_estadual_destinatario':
          destinatario.indicadorInscricaoEstadual,
      'logradouro_destinatario': destinatario.logradouro,
      'numero_destinatario': destinatario.numero,
      'bairro_destinatario': destinatario.bairro,
      'municipio_destinatario': destinatario.municipio,
      'codigo_municipio_destinatario': destinatario.codigoMunicipioIbge,
      'uf_destinatario': destinatario.uf,
      'cep_destinatario': destinatario.cep.replaceAll(RegExp(r'\D'), ''),
      'pais_destinatario': 'Brasil',
      'modalidade_frete': modalidadeFrete.toString(),
      'volumes': [
        {
          'quantidade_volumes': log.volumes > 0 ? log.volumes : 1,
          'especie': log.especieVolumes,
          'peso_bruto': _formatarDecimal(
            log.pesoBrutoKg > 0 ? log.pesoBrutoKg : log.volumes.toDouble(),
          ),
        },
      ],
      'valor_produtos': _formatarDecimal(valorProdutos),
      'valor_desconto': _formatarDecimal(desconto),
      'valor_frete': _formatarDecimal(frete),
      'valor_total': _formatarDecimal(valorTotal),
      'items': itens,
      'formas_pagamento': _formasPagamentoDeVenda(venda, valorTotal),
      'informacoes_adicionais_contribuinte': _observacaoVenda(venda),
      ...NfeCobrancaHelper.montarCamposFocus(venda),
    };

    if (doc.length == 11) {
      payload['cpf_destinatario'] = doc;
    } else {
      payload['cnpj_destinatario'] = doc;
    }
    if (destinatario.telefone.isNotEmpty) {
      payload['telefone_destinatario'] = destinatario.telefone;
    }
    if (destinatario.email.isNotEmpty) {
      payload['email_destinatario'] = destinatario.email;
    }
    if (destinatario.complemento.isNotEmpty) {
      payload['complemento_destinatario'] = destinatario.complemento;
    }
    final placa = log.placaVeiculo.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (placa.length >= 7) {
      payload['placa_veiculo'] = placa;
    }

    return payload;
  }

  /// Referencia estavel para NF-e de devolucao vinculada a um registro interno.
  static String referenciaDevolucaoVenda({
    required int vendaId,
    required int registroDevolucaoId,
  }) =>
      'venda_${vendaId}_dev_$registroDevolucaoId';

  /// Referencia estavel para NF-e de devolucao de compra (loja → fornecedor).
  static String referenciaDevolucaoCompra({
    required String chaveNotaCompra,
    required int sequencia,
  }) {
    final chave = chaveNotaCompra.replaceAll(RegExp(r'\D'), '');
    return 'dev_compra_${chave}_$sequencia';
  }

  /// Emite NF-e modelo 55 de devolucao (finalidade 4) referenciando a nota original.
  Future<FocusNfeEmissaoResultado> emitirNfeDevolucao({
    required String referencia,
    required String chaveNotaOriginal,
    required FocusNfeDestinatarioNfe destinatario,
    required List<FocusNfeItemDevolucao> itensDevolucao,
    String motivo = '',
  }) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeEmissaoResultado.erro('Referencia da devolucao invalida.');
    }
    final chave = chaveNotaOriginal.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      return FocusNfeEmissaoResultado.erro(
        'Chave da nota original invalida para devolucao fiscal.',
      );
    }
    if (itensDevolucao.isEmpty) {
      return FocusNfeEmissaoResultado.erro(
        'Informe ao menos um item na devolucao fiscal.',
      );
    }

    final payload = montarPayloadNfeDevolucao(
      chaveNotaOriginal: chave,
      destinatario: destinatario,
      itensDevolucao: itensDevolucao,
      motivo: motivo,
    );
    return _postDocumento(
      uri: Uri.parse(_config.endpointNfe(ref)),
      payload: payload,
      referencia: ref,
    );
  }

  /// Emite NF-e de devolucao de compra (saida, CFOP 5202/6202) ao fornecedor/fabrica.
  Future<FocusNfeEmissaoResultado> emitirNfeDevolucaoFornecedor({
    required String referencia,
    required String chaveNotaCompra,
    required FocusNfeDestinatarioNfe destinatario,
    required List<FocusNfeItemDevolucao> itensDevolucao,
    String motivo = '',
  }) async {
    validarConfiguracao();
    final ref = referencia.trim();
    if (ref.isEmpty) {
      return FocusNfeEmissaoResultado.erro('Referencia da devolucao invalida.');
    }
    final chave = chaveNotaCompra.replaceAll(RegExp(r'\D'), '');
    if (chave.length != 44) {
      return FocusNfeEmissaoResultado.erro(
        'Chave da NF-e de compra invalida para devolucao ao fornecedor.',
      );
    }
    if (itensDevolucao.isEmpty) {
      return FocusNfeEmissaoResultado.erro(
        'Informe ao menos um item na devolucao ao fornecedor.',
      );
    }

    final payload = montarPayloadNfeDevolucaoFornecedor(
      chaveNotaCompra: chave,
      destinatario: destinatario,
      itensDevolucao: itensDevolucao,
      motivo: motivo,
    );
    return _postDocumento(
      uri: Uri.parse(_config.endpointNfe(ref)),
      payload: payload,
      referencia: ref,
    );
  }

  Map<String, dynamic> montarPayloadNfeDevolucao({
    required String chaveNotaOriginal,
    required FocusNfeDestinatarioNfe destinatario,
    required List<FocusNfeItemDevolucao> itensDevolucao,
    String motivo = '',
  }) {
    destinatario.validar();

    final ufDestino = destinatario.uf.trim().toUpperCase();
    final consumidorFinal = _consumidorFinalNfe(destinatario);
    final itens = <Map<String, dynamic>>[];
    var numero = 1;
    for (final linha in itensDevolucao) {
      if (linha.quantidade <= 0) continue;
      itens.add(
        _itemFocusDevolucao(
          numeroItem: numero++,
          produto: linha.produto,
          descricao: linha.descricao,
          quantidade: linha.quantidade,
          valorUnitario: linha.valorUnitario,
          ufDestino: ufDestino,
        ),
      );
    }
    if (itens.isEmpty) {
      throw FocusNfeValidacaoException('Itens de devolucao invalidos.');
    }

    final valorProdutos = _somaValorBrutoItens(itens);
    final valorTotal = valorProdutos.clamp(0, double.infinity).toDouble();
    final doc = destinatario.documento.replaceAll(RegExp(r'\D'), '');
    final ieDest = destinatario.inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
    final obs = motivo.trim().isEmpty
        ? 'Devolucao de mercadoria conforme registro interno.'
        : motivo.trim();

    final payload = <String, dynamic>{
      ..._camposEmitenteFocus(),
      ..._camposTipoEmissao(tipoEmissao: FocusNfeEmissaoSefaz.tipoEmissaoNormal),
      'natureza_operacao': 'Devolucao de venda de mercadoria',
      'data_emissao': _isoEmissao.format(DateTime.now()),
      'tipo_documento': '0',
      'local_destino': _localDestino(
        ufDestino,
        ufDestinatario: ufDestino,
      ),
      'finalidade_emissao': '4',
      'consumidor_final': consumidorFinal ? '1' : '0',
      'presenca_comprador': '1',
      'nome_destinatario': destinatario.nome,
      if (ieDest.isNotEmpty) 'inscricao_estadual_destinatario': ieDest,
      'indicador_inscricao_estadual_destinatario':
          destinatario.indicadorInscricaoEstadual,
      'logradouro_destinatario': destinatario.logradouro,
      'numero_destinatario': destinatario.numero,
      'bairro_destinatario': destinatario.bairro,
      'municipio_destinatario': destinatario.municipio,
      'codigo_municipio_destinatario': destinatario.codigoMunicipioIbge,
      'uf_destinatario': destinatario.uf,
      'cep_destinatario': destinatario.cep.replaceAll(RegExp(r'\D'), ''),
      'pais_destinatario': 'Brasil',
      'modalidade_frete': '9',
      'valor_produtos': _formatarDecimal(valorProdutos),
      'valor_desconto': _formatarDecimal(0),
      'valor_frete': _formatarDecimal(0),
      'valor_total': _formatarDecimal(valorTotal),
      'items': itens,
      'formas_pagamento': [
        {
          'forma_pagamento': '90',
          'valor_pagamento': _formatarDecimal(0),
        },
      ],
      'informacoes_adicionais_contribuinte': obs,
      'notas_referenciadas': [
        {'chave_nfe': chaveNotaOriginal},
      ],
    };

    if (doc.length == 11) {
      payload['cpf_destinatario'] = doc;
    } else {
      payload['cnpj_destinatario'] = doc;
    }
    if (destinatario.telefone.isNotEmpty) {
      payload['telefone_destinatario'] = destinatario.telefone;
    }
    if (destinatario.email.isNotEmpty) {
      payload['email_destinatario'] = destinatario.email;
    }
    if (destinatario.complemento.isNotEmpty) {
      payload['complemento_destinatario'] = destinatario.complemento;
    }

    return payload;
  }

  /// Payload Focus: saida (tpNF=1), finalidade 4, CFOP 5202/6202 (ou ST),
  /// referenciando a chave da NF-e de compra — padrao ERP material de construcao.
  Map<String, dynamic> montarPayloadNfeDevolucaoFornecedor({
    required String chaveNotaCompra,
    required FocusNfeDestinatarioNfe destinatario,
    required List<FocusNfeItemDevolucao> itensDevolucao,
    String motivo = '',
  }) {
    destinatario.validar();

    final ufDestino = destinatario.uf.trim().toUpperCase();
    final itens = <Map<String, dynamic>>[];
    var numero = 1;
    for (final linha in itensDevolucao) {
      if (linha.quantidade <= 0) continue;
      itens.add(
        _itemFocusDevolucaoFornecedor(
          numeroItem: numero++,
          produto: linha.produto,
          descricao: linha.descricao,
          quantidade: linha.quantidade,
          valorUnitario: linha.valorUnitario,
          ufDestino: ufDestino,
          cfopOverride: linha.cfopOverride,
          icmsOrigem: linha.icmsOrigem,
          icmsSituacaoTributaria: linha.icmsSituacaoTributaria,
          icmsBaseCalculo: linha.icmsBaseCalculo,
          icmsAliquota: linha.icmsAliquota,
          icmsValor: linha.icmsValor,
          icmsBaseCalculoSt: linha.icmsBaseCalculoSt,
          icmsAliquotaSt: linha.icmsAliquotaSt,
          icmsValorSt: linha.icmsValorSt,
          ipiValor: linha.ipiValor,
        ),
      );
    }
    if (itens.isEmpty) {
      throw FocusNfeValidacaoException(
        'Itens de devolucao ao fornecedor invalidos.',
      );
    }

    final valorProdutos = _somaValorBrutoItens(itens);
    final valorTotal = valorProdutos.clamp(0, double.infinity).toDouble();
    final doc = destinatario.documento.replaceAll(RegExp(r'\D'), '');
    final ieDest = destinatario.inscricaoEstadual.replaceAll(RegExp(r'\D'), '');
    final obs = motivo.trim().isEmpty
        ? 'Devolucao de compra ao fornecedor conforme NF-e referenciada.'
        : motivo.trim();

    final payload = <String, dynamic>{
      ..._camposEmitenteFocus(),
      ..._camposTipoEmissao(tipoEmissao: FocusNfeEmissaoSefaz.tipoEmissaoNormal),
      'natureza_operacao': 'Devolucao de compra',
      'data_emissao': _isoEmissao.format(DateTime.now()),
      'tipo_documento': '1',
      'local_destino': _localDestino(
        ufDestino,
        ufDestinatario: ufDestino,
      ),
      'finalidade_emissao': '4',
      'consumidor_final': '0',
      'presenca_comprador': '1',
      'nome_destinatario': destinatario.nome,
      if (ieDest.isNotEmpty) 'inscricao_estadual_destinatario': ieDest,
      'indicador_inscricao_estadual_destinatario':
          destinatario.indicadorInscricaoEstadual,
      'logradouro_destinatario': destinatario.logradouro,
      'numero_destinatario': destinatario.numero,
      'bairro_destinatario': destinatario.bairro,
      'municipio_destinatario': destinatario.municipio,
      'codigo_municipio_destinatario': destinatario.codigoMunicipioIbge,
      'uf_destinatario': destinatario.uf,
      'cep_destinatario': destinatario.cep.replaceAll(RegExp(r'\D'), ''),
      'pais_destinatario': 'Brasil',
      'modalidade_frete': '9',
      'valor_produtos': _formatarDecimal(valorProdutos),
      'valor_desconto': _formatarDecimal(0),
      'valor_frete': _formatarDecimal(0),
      'valor_total': _formatarDecimal(valorTotal),
      'items': itens,
      'formas_pagamento': [
        {
          'forma_pagamento': '90',
          'valor_pagamento': _formatarDecimal(0),
        },
      ],
      'informacoes_adicionais_contribuinte': obs,
      'notas_referenciadas': [
        {'chave_nfe': chaveNotaCompra},
      ],
    };

    if (doc.length == 11) {
      payload['cpf_destinatario'] = doc;
    } else {
      payload['cnpj_destinatario'] = doc;
    }
    if (destinatario.telefone.isNotEmpty) {
      payload['telefone_destinatario'] = destinatario.telefone;
    }
    if (destinatario.email.isNotEmpty) {
      payload['email_destinatario'] = destinatario.email;
    }
    if (destinatario.complemento.isNotEmpty) {
      payload['complemento_destinatario'] = destinatario.complemento;
    }

    return payload;
  }

  Map<String, dynamic> _itemFocusDevolucao({
    required int numeroItem,
    required Produto produto,
    required String descricao,
    required int quantidade,
    required double valorUnitario,
    required String ufDestino,
  }) {
    final ncm = _resolverNcm(produto);
    final cfop = NfeCfopDevolucaoResolver.resolver(
      produto: produto,
      ufDestinatario: ufDestino,
      ufEmitente: _config.ufEmitente,
    );
    final unidade = FiscalService.normalizarUnidadeFiscal(produto.unidade);
    final valorBruto = quantidade * valorUnitario;
    final codigo = produto.codigoInterno.trim().isEmpty
        ? 'ID-${produto.id}'
        : produto.codigoInterno.trim();
    final gtin = _codigoBarrasFocus(produto);
    final trib = _tributacaoItemPadrao(produto, valorBruto: valorBruto);
    final cest = FiscalService.normalizarCest(produto.cest);

    return {
      'numero_item': numeroItem.toString(),
      'codigo_produto': codigo,
      'descricao': descricao.trim().isEmpty
          ? ProdutoNomeExibicao.paraImpressao(produto)
          : descricao.trim(),
      'codigo_barras_comercial': gtin,
      'codigo_barras_tributavel': gtin,
      'cfop': cfop,
      'unidade_comercial': unidade.toLowerCase(),
      'quantidade_comercial': _formatarQuantidade(quantidade),
      'valor_unitario_comercial': _formatarDecimal(valorUnitario),
      'unidade_tributavel': unidade.toLowerCase(),
      'quantidade_tributavel': _formatarQuantidade(quantidade),
      'valor_unitario_tributavel': _formatarDecimal(valorUnitario),
      'codigo_ncm': ncm,
      if (cest.length == 7) 'cest': cest,
      'valor_bruto': _formatarDecimal(valorBruto),
      'inclui_no_total': '1',
      ...trib,
    };
  }

  Map<String, dynamic> _itemFocusDevolucaoFornecedor({
    required int numeroItem,
    required Produto produto,
    required String descricao,
    required int quantidade,
    required double valorUnitario,
    required String ufDestino,
    String cfopOverride = '',
    String icmsOrigem = '',
    String icmsSituacaoTributaria = '',
    double? icmsBaseCalculo,
    double? icmsAliquota,
    double? icmsValor,
    double? icmsBaseCalculoSt,
    double? icmsAliquotaSt,
    double? icmsValorSt,
    double? ipiValor,
  }) {
    final ncm = _resolverNcm(produto);
    final cfop = cfopOverride.trim().isNotEmpty
        ? cfopOverride.trim()
        : NfeCfopDevolucaoFornecedorResolver.resolver(
            produto: produto,
            ufDestinatario: ufDestino,
            ufEmitente: _config.ufEmitente,
          );
    final unidade = FiscalService.normalizarUnidadeFiscal(produto.unidade);
    final valorBruto = quantidade * valorUnitario;
    final codigo = produto.codigoInterno.trim().isEmpty
        ? 'ID-${produto.id}'
        : produto.codigoInterno.trim();
    final gtin = _codigoBarrasFocus(produto);
    final trib = _tributacaoItemPadrao(produto, valorBruto: valorBruto);
    final cest = FiscalService.normalizarCest(produto.cest);

    if (icmsOrigem.trim().isNotEmpty) {
      trib['icms_origem'] = icmsOrigem.trim();
    }
    if (icmsSituacaoTributaria.trim().isNotEmpty) {
      trib['icms_situacao_tributaria'] = icmsSituacaoTributaria.trim();
      if (IcmsFocusItemHelper.cstExigeModalidadeBaseCalculo(
        icmsSituacaoTributaria,
      )) {
        trib['icms_modalidade_base_calculo'] =
            IcmsFocusItemHelper.modalidadeBaseValorOperacao;
      }
    }
    if (icmsBaseCalculo != null && icmsBaseCalculo >= 0) {
      trib['icms_base_calculo'] = _formatarDecimal(icmsBaseCalculo);
    }
    if (icmsAliquota != null && icmsAliquota >= 0) {
      trib['icms_aliquota'] = _formatarDecimal(icmsAliquota);
    }
    if (icmsValor != null && icmsValor >= 0) {
      trib['icms_valor'] = _formatarDecimal(icmsValor);
    }
    if (icmsBaseCalculoSt != null && icmsBaseCalculoSt > 0) {
      trib['icms_base_calculo_st'] = _formatarDecimal(icmsBaseCalculoSt);
    }
    if (icmsAliquotaSt != null && icmsAliquotaSt > 0) {
      trib['icms_aliquota_st'] = _formatarDecimal(icmsAliquotaSt);
    }
    if (icmsValorSt != null && icmsValorSt > 0) {
      trib['icms_valor_st'] = _formatarDecimal(icmsValorSt);
    }
    if (ipiValor != null && ipiValor > 0) {
      trib['ipi_situacao_tributaria'] = '99';
      trib['ipi_codigo_enquadramento_legal'] = '999';
      trib['ipi_valor'] = _formatarDecimal(ipiValor);
    }

    return {
      'numero_item': numeroItem.toString(),
      'codigo_produto': codigo,
      'descricao': descricao.trim().isEmpty
          ? ProdutoNomeExibicao.paraImpressao(produto)
          : descricao.trim(),
      'codigo_barras_comercial': gtin,
      'codigo_barras_tributavel': gtin,
      'cfop': cfop,
      'unidade_comercial': unidade.toLowerCase(),
      'quantidade_comercial': _formatarQuantidade(quantidade),
      'valor_unitario_comercial': _formatarDecimal(valorUnitario),
      'unidade_tributavel': unidade.toLowerCase(),
      'quantidade_tributavel': _formatarQuantidade(quantidade),
      'valor_unitario_tributavel': _formatarDecimal(valorUnitario),
      'codigo_ncm': ncm,
      if (cest.length == 7) 'cest': cest,
      'valor_bruto': _formatarDecimal(valorBruto),
      'inclui_no_total': '1',
      ...trib,
    };
  }

  Map<String, dynamic> _camposEmitenteFocus() {
    final ie = FocusNfeConfig._somenteDigitos(_config.inscricaoEstadualEmitente);
    return {
      'cnpj_emitente': FocusNfeConfig._somenteDigitos(_config.cnpjEmitente),
      if (ie.isNotEmpty) 'inscricao_estadual_emitente': ie,
      'regime_tributario_emitente':
          _config.regimeTributarioEmitente.clamp(1, 3).toString(),
      'uf_emitente': _config.ufEmitente.trim().toUpperCase(),
    };
  }

  Map<String, dynamic> _camposTipoEmissao({
    required String tipoEmissao,
    FocusNfeFormaEmissaoUrl formaEmissao = FocusNfeFormaEmissaoUrl.normal,
    bool incluirFormaEmissaoNoCorpo = false,
  }) {
    final campos = <String, dynamic>{
      'tipo_emissao': tipoEmissao,
    };
    if (incluirFormaEmissaoNoCorpo &&
        formaEmissao == FocusNfeFormaEmissaoUrl.contingenciaOfflineNfce) {
      campos['forma_emissao'] = 'offline';
    }
    return campos;
  }

  static bool _deveTentarContingenciaNfce(FocusNfeEmissaoResultado resultado) {
    return pareceFalhaComunicacao(resultado);
  }

  /// Timeout/rede/indisponibilidade — candidato a reconsulta antes de tratar como falha.
  static bool pareceFalhaComunicacao(FocusNfeEmissaoResultado resultado) {
    if (resultado.autorizada || resultado.processando) return false;

    // Rejeicao fiscal da SEFAZ (HTTP 2xx) nao e falha de rede.
    if (resultado.rejeitada &&
        resultado.statusSefaz.isNotEmpty &&
        resultado.httpStatusCode >= 200 &&
        resultado.httpStatusCode < 300) {
      return false;
    }

    final http = resultado.httpStatusCode;
    if (http == 408 ||
        http == 502 ||
        http == 503 ||
        http == 504 ||
        http == 429) {
      return true;
    }

    final msg = resultado.mensagem.toLowerCase();

    const exclusoesRejeicaoFiscal = [
      'data-hora',
      'posterior ao horario',
      'posterior ao horário',
      'rejeicao:',
      'rejeição:',
      'cfop',
      'cst',
      'ncm',
      'cest',
      'cnpj',
      'cpf',
      'inscricao',
      'inscrição',
      'csc',
      'duplicidade',
      'denegad',
      'ibs',
      'cbs',
      'classifica',
    ];
    for (final e in exclusoesRejeicaoFiscal) {
      if (msg.contains(e)) return false;
    }

    const gatilhos = [
      'timeout',
      'timed out',
      'indispon',
      'temporariamente',
      'falha de comunicacao',
      'falha de comunicação',
      'falha ao comunicar',
      'erro de conexao',
      'erro de conexão',
      'connection refused',
      'connection reset',
      'host lookup',
      'socketexception',
      'handshake',
    ];
    for (final g in gatilhos) {
      if (msg.contains(g)) return true;
    }
    return false;
  }

  Future<FocusNfeEmissaoResultado> _postDocumento({
    required Uri uri,
    required Map<String, dynamic> payload,
    required String referencia,
    bool contingenciaOffline = false,
  }) async {
    try {
      final bodyJson = const JsonEncoder.withIndent('  ').convert(payload);
      debugPrint(
        '========== Focus NFe POST $referencia ==========\n'
        'URI: $uri\n'
        '$bodyJson\n'
        '===============================================',
      );

      final response = await _http
          .post(
            uri,
            headers: _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      Map<String, dynamic>? jsonBody;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          jsonBody = decoded;
        } else if (decoded is Map) {
          jsonBody = decoded.cast<String, dynamic>();
        }
      } catch (_) {}

      if (jsonBody == null) {
        return FocusNfeEmissaoResultado.erro(
          'Resposta invalida da Focus NFe (HTTP ${response.statusCode}).',
          httpStatusCode: response.statusCode,
        );
      }

      if (response.statusCode == 422 || response.statusCode == 400) {
        final erros = jsonBody['erros'] ?? jsonBody['errors'];
        final msg = _extrairMensagemErroApi(jsonBody, erros);
        return FocusNfeEmissaoResultado.erro(
          msg,
          httpStatusCode: response.statusCode,
          payloadBruto: jsonBody,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return FocusNfeEmissaoResultado.erro(
          _extrairMensagemErroApi(jsonBody, null),
          httpStatusCode: response.statusCode,
          payloadBruto: jsonBody,
        );
      }

      final resultado = FocusNfeEmissaoResultado.deRespostaFocus(
        jsonBody,
        referencia: referencia,
        httpStatusCode: response.statusCode,
        apiBaseUrl: _config.baseUrl,
      );

      if (resultado.rejeitada && resultado.mensagem.isEmpty) {
        return FocusNfeEmissaoResultado.erro(
          'Documento fiscal rejeitado.',
          httpStatusCode: response.statusCode,
          payloadBruto: jsonBody,
        );
      }

      if (contingenciaOffline && resultado.mensagem.isNotEmpty) {
        return FocusNfeEmissaoResultado(
          autorizada: resultado.autorizada,
          rejeitada: resultado.rejeitada,
          processando: resultado.processando,
          statusFocus: resultado.statusFocus,
          statusSefaz: resultado.statusSefaz,
          chaveNfe: resultado.chaveNfe,
          numero: resultado.numero,
          serie: resultado.serie,
          protocolo: resultado.protocolo,
          urlDanfe: resultado.urlDanfe,
          urlXml: resultado.urlXml,
          mensagem:
              '${resultado.mensagem} (NFC-e emitida em contingencia offline.)',
          referencia: resultado.referencia,
          httpStatusCode: resultado.httpStatusCode,
          payloadBruto: resultado.payloadBruto,
        );
      }

      return resultado;
    } catch (e) {
      final msg = e is TimeoutException || e is SocketException
          ? 'Falha de comunicacao com a Focus/SEFAZ (timeout ou rede): $e'
          : 'Falha ao comunicar com a Focus NFe: $e';
      return FocusNfeEmissaoResultado.erro(msg);
    }
  }

  Map<String, String> _headers() {
    final token = _config.apiToken.trim();
    final basic = base64Encode(utf8.encode('$token:'));
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Basic $basic',
    };
  }

  static bool _consumidorFinalNfe(FocusNfeDestinatarioNfe destinatario) {
    final doc = destinatario.documento.replaceAll(RegExp(r'\D'), '');
    if (doc.length == 11) return true;
    return destinatario.indicadorInscricaoEstadual == '9';
  }

  List<Map<String, dynamic>> _itensFocusDeVenda(
    Venda venda, {
    required String ufDestino,
    bool emissaoNfe = false,
    bool consumidorFinal = true,
    List<ItemVenda>? itens,
    Produto? Function(int id)? obterProduto,
  }) {
    final lista = <Map<String, dynamic>>[];
    var numero = 1;
    List<ItemVenda> linhas;
    if (itens != null && itens.isNotEmpty) {
      linhas = itens;
    } else {
      try {
        linhas = List<ItemVenda>.from(venda.itens);
      } catch (_) {
        linhas = const [];
      }
    }
    for (final item in linhas) {
      if (item.quantidade <= 0) continue;
      Produto? produto;
      try {
        produto = item.produto.target;
      } catch (_) {}
      produto ??= obterProduto?.call(item.produto.targetId);
      if (produto == null) {
        throw FocusNfeValidacaoException(
          'Item "${item.nomeProduto}" sem produto vinculado.',
        );
      }
      lista.add(
        _itemFocus(
          numeroItem: numero++,
          produto: produto,
          descricao: ProdutoNomeExibicao.paraImpressaoItem(item),
          quantidade: item.quantidadeVendaEfetiva,
          valorUnitario: item.precoUnitario,
          ufDestino: ufDestino,
          emissaoNfe: emissaoNfe,
          consumidorFinal: consumidorFinal,
        ),
      );
    }
    return lista;
  }

  Map<String, dynamic> _itemFocus({
    required int numeroItem,
    required Produto produto,
    required String descricao,
    required num quantidade,
    required double valorUnitario,
    required String ufDestino,
    bool emissaoNfe = false,
    bool consumidorFinal = true,
  }) {
    final ncm = _resolverNcm(produto);
    final cfop = emissaoNfe
        ? NfeCfopResolver.resolver(
            produto: produto,
            ufDestinatario: ufDestino,
            consumidorFinal: consumidorFinal,
            ufEmitente: _config.ufEmitente,
          )
        : _resolverCfopNfce(produto, ufDestino: ufDestino);
    final unidade = FiscalService.normalizarUnidadeFiscal(produto.unidade);
    final valorBruto = quantidade.toDouble() * valorUnitario;
    final codigo = produto.codigoInterno.trim().isEmpty
        ? 'ID-${produto.id}'
        : produto.codigoInterno.trim();
    final gtin = _codigoBarrasFocus(produto);

    final trib = _tributacaoItemPadrao(produto, valorBruto: valorBruto);
    final cest = FiscalService.normalizarCest(produto.cest);

    return {
      'numero_item': numeroItem.toString(),
      'codigo_produto': codigo,
      'descricao': descricao.trim().isEmpty
          ? ProdutoNomeExibicao.paraImpressao(produto)
          : descricao.trim(),
      'codigo_barras_comercial': gtin,
      'codigo_barras_tributavel': gtin,
      'cfop': cfop,
      'unidade_comercial': unidade.toLowerCase(),
      'quantidade_comercial': _formatarQuantidade(quantidade),
      'valor_unitario_comercial': _formatarDecimal(valorUnitario),
      'unidade_tributavel': unidade.toLowerCase(),
      'quantidade_tributavel': _formatarQuantidade(quantidade),
      'valor_unitario_tributavel': _formatarDecimal(valorUnitario),
      'codigo_ncm': ncm,
      if (cest.length == 7) 'cest': cest,
      'valor_bruto': _formatarDecimal(valorBruto),
      'inclui_no_total': '1',
      ...trib,
    };
  }

  /// Tributacao padrao Regime Normal (Lucro Presumido/Real — Matcon).
  ///
  /// - ICMS origem 0 (Nacional)
  /// - CST 00 na maioria dos itens tributados (balcao)
  /// - PIS/COFINS 01 (operacao tributavel, aliquota basica)
  /// - IBS/CBS CST 000 + cClassTrib 000001 (fase testes 2026)
  ///
  /// Ajuste por [Produto.grupoTributario] (ST / isento). Quando o cadastro
  /// passar a ter CST por produto, mapeie em [_resolverIcmsSituacaoTributariaItem].
  Map<String, dynamic> _tributacaoItemPadrao(
    Produto produto, {
    required double valorBruto,
  }) {
    return {
      ...IcmsFocusItemHelper.camposIcmsItem(
        icmsOrigem: _resolverIcmsOrigemItem(produto),
        icmsSituacaoTributaria: _resolverIcmsSituacaoTributariaItem(produto),
      ),
      'pis_situacao_tributaria': _resolverPisCofinsItem(produto),
      'cofins_situacao_tributaria': _resolverPisCofinsItem(produto),
      ...IbscbsFocusItemHelper.camposItem(baseCalculo: valorBruto),
    };
  }

  String _resolverIcmsOrigemItem(Produto produto) {
    return ProdutoFiscalCatalog.resolverIcmsOrigem(produto);
  }

  String _resolverIcmsSituacaoTributariaItem(Produto produto) {
    final regime = _config.regimeTributarioEmitente;
    final ehSimples = regime == 1 || regime == 2;
    return ProdutoFiscalCatalog.resolverIcmsSituacaoTributaria(
      produto,
      icmsPadraoLoja: _config.icmsSituacaoTributariaPadrao,
      ehSimplesNacional: ehSimples,
    );
  }

  String _resolverPisCofinsItem(Produto produto) {
    return ProdutoFiscalCatalog.resolverPisCofinsSituacaoTributaria(
      produto,
      pisCofinsPadraoLoja: _config.pisCofinsSituacaoPadrao,
    );
  }

  String _resolverNcm(Produto produto) {
    final cadastro = FiscalService.normalizarNcm(produto.ncm);
    if (cadastro.replaceAll('0', '').isNotEmpty &&
        cadastro.length == 8) {
      return cadastro;
    }
    return FiscalService.normalizarNcm(_config.ncmPadrao);
  }

  String _resolverCfopNfce(Produto produto, {required String ufDestino}) {
    return _fiscal.resolverCfopVenda(
      produto: produto,
      ufDestino: ufDestino,
      consumidorFinal: true,
      operacaoInterna:
          ufDestino.trim().toUpperCase() == _config.ufEmitente.toUpperCase(),
    );
  }

  static String _codigoBarrasFocus(Produto produto) {
    final digits = produto.codigoBarras.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8 ||
        digits.length == 12 ||
        digits.length == 13 ||
        digits.length == 14) {
      return digits;
    }
    return 'SEM GTIN';
  }

  List<Map<String, dynamic>> _formasPagamentoDeVenda(
    Venda venda,
    double valorTotal,
  ) {
    final linhas = <Map<String, dynamic>>[];

    if (venda.formaPagamento == 'misto' &&
        venda.pagamentosJson.trim().isNotEmpty) {
      for (final l in PagamentoOrcamentoCodec.decode(venda.pagamentosJson)) {
        linhas.add({
          'forma_pagamento': _codigoFormaPagamentoFocus(l.meio),
          'valor_pagamento': _formatarDecimal(l.valor),
        });
      }
    } else {
      linhas.add({
        'forma_pagamento': _codigoFormaPagamentoFocus(venda.formaPagamento),
        'valor_pagamento': _formatarDecimal(valorTotal),
      });
    }

    if (linhas.isEmpty) {
      linhas.add({
        'forma_pagamento': '01',
        'valor_pagamento': _formatarDecimal(valorTotal),
      });
    }
    return linhas;
  }

  static String _codigoFormaPagamentoFocus(String meio) {
    switch (meio.trim().toLowerCase()) {
      case 'dinheiro':
        return '01';
      case 'cheque':
        return '02';
      case 'cartao_credito':
        return '03';
      case 'cartao_debito':
        return '04';
      case 'fiado':
      case 'credito_loja':
        return '05';
      case 'pix':
        return '17';
      case 'vale_alimentacao':
        return '10';
      case 'vale_refeicao':
        return '11';
      case 'boleto':
        return '15';
      default:
        return '99';
    }
  }

  static String? _documentoDestinatario(Cliente? cliente) {
    if (cliente == null) return null;
    final doc = cliente.documento.replaceAll(RegExp(r'\D'), '');
    if (doc.length == 11 || doc.length == 14) return doc;
    return null;
  }

  static String _localDestino(String ufDestino, {String? ufDestinatario}) {
    final emitente = FiscalConfig.ufEmitente.toUpperCase();
    final dest = (ufDestinatario ?? ufDestino).trim().toUpperCase();
    if (dest.isEmpty || dest == emitente) return '1';
    return '2';
  }

  /// `venda_{id}` (NFC-e) ou `venda_{id}_nfe` (NF-e 55) — mesma [ref] reenvia a mesma nota.
  static String _referenciaVenda(Venda venda, String sufixoDocumento) {
    if (venda.id > 0) {
      if (sufixoDocumento == 'nfe') return 'venda_${venda.id}_nfe';
      return 'venda_${venda.id}';
    }
    return 'venda_tmp_${DateTime.now().millisecondsSinceEpoch}_$sufixoDocumento';
  }

  static String _observacaoVenda(Venda venda) =>
      VendaDocumentoRotuloHelper.observacaoFiscalNota(venda);

  static double _somaValorBrutoItens(List<Map<String, dynamic>> itens) {
    var total = 0.0;
    for (final item in itens) {
      final bruto = double.tryParse(item['valor_bruto']?.toString() ?? '') ?? 0;
      total += bruto;
    }
    return total;
  }

  static String _formatarDecimal(num valor) => valor.toStringAsFixed(2);

  static String _formatarQuantidade(num qtd) {
    if (qtd == qtd.roundToDouble()) {
      return qtd.round().toString();
    }
    return qtd.toStringAsFixed(4);
  }

  static String _extrairMensagemErroApi(
    Map<String, dynamic> json,
    Object? erros,
  ) {
    final buf = StringBuffer();
    final msg = (json['mensagem'] ?? json['message'] ?? '').toString().trim();
    final sefaz = (json['mensagem_sefaz'] ?? '').toString().trim();
    if (sefaz.isNotEmpty) buf.writeln(sefaz);
    if (msg.isNotEmpty) buf.writeln(msg);

    if (erros is List) {
      for (final e in erros) {
        if (e is Map) {
          final campo = (e['campo'] ?? e['field'] ?? '').toString();
          final m = (e['mensagem'] ?? e['message'] ?? e['erro'] ?? '')
              .toString();
          if (m.isNotEmpty) {
            buf.writeln(campo.isEmpty ? m : '$campo: $m');
          }
        }
      }
    } else if (erros is Map) {
      for (final entry in erros.entries) {
        buf.writeln('${entry.key}: ${entry.value}');
      }
    }

    final texto = buf.toString().trim();
    return texto.isEmpty ? 'Erro na API Focus NFe.' : texto;
  }
}

String _indicadorIeCliente(Cliente cliente) {
  final ind = cliente.indicadorIe.trim().toLowerCase();
  if (ind == 'contribuinte') return '1';
  if (ind == 'isento') return '2';
  if (cliente.inscricaoEstadual.replaceAll(RegExp(r'\D'), '').isNotEmpty) {
    return '1';
  }
  return '9';
}

class FocusNfeValidacaoException implements Exception {
  FocusNfeValidacaoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FocusNfeConfigIncompletaException implements Exception {
  FocusNfeConfigIncompletaException(this.message);
  final String message;
  @override
  String toString() => message;
}

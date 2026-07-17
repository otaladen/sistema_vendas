/// Parametros fiscais padrao (Focus NFe — NFC-e / NF-e).
///
/// **Token Focus:** nao fica neste arquivo. Configure em
/// Configuracoes → Fiscal — Focus NFe (gravado localmente no PC).
/// Nunca commitar token real no Git.
class FiscalConfig {
  const FiscalConfig._();

  /// URL base da API Focus NFe.
  ///
  /// Homologacao: notas de teste, sem validade juridica.
  /// Producao: `https://api.focusnfe.com.br` (defina o ambiente na tela Fiscal).
  static const String apiBaseUrl = 'https://homologacao.focusnfe.com.br';

  /// Token vazio no codigo — use [FiscalConfigStore] / tela de Configuracoes.
  static const String apiToken = '';

  /// Razao social do emitente (cabecalho contabil / Excel).
  static const String razaoSocialEmitente =
      'COMPROU LEVOU MATERIAIS DE CONSTRUÇÃO LTDA';

  /// CNPJ da loja emitente (14 digitos, somente numeros).
  static const String cnpjEmitente = '32662298000191';

  /// Inscricao Estadual do emitente (somente numeros; obrigatoria na Focus).
  static const String inscricaoEstadualEmitente = '025232204';

  /// Regime tributario do emitente (Focus: regime_tributario_emitente).
  /// 1 = Simples Nacional | 2 = SN excesso sublimite | 3 = Regime Normal.
  static const int regimeTributarioEmitente = 3;

  /// CFOP padrao venda interna (planilha quando o XML nao informar).
  static const String cfopPadraoVendaInterna = '5102';

  /// NF-e estadual (BA) — venda a contribuinte (construtora / revenda).
  static const String cfopEstadualContribuinteTributado = '5101';

  /// NF-e estadual (BA) — mercadoria com ST para contribuinte.
  static const String cfopEstadualContribuinteSt = '5401';

  /// NF-e interestadual — revenda tributada (padrao atacado).
  static const String cfopInterestadualTributadoRevenda = '6102';

  /// NF-e interestadual — industrializacao / producao propria (ajuste com contador).
  static const String cfopInterestadualTributadoIndustrial = '6101';

  /// NF-e interestadual — ST (substituicao tributaria).
  static const String cfopInterestadualSt = '6403';

  /// Devolucao de venda (cliente devolve) — mesma UF (entrada).
  static const String cfopDevolucaoVendaEstadual = '1202';

  /// Devolucao de venda — interestadual (entrada).
  static const String cfopDevolucaoVendaInterestadual = '2202';

  /// Devolucao de venda com ST — mesma UF.
  static const String cfopDevolucaoVendaEstadualSt = '1411';

  /// Devolucao de compra para comercializacao (loja → fabrica/fornecedor), estadual.
  static const String cfopDevolucaoCompraEstadual = '5202';

  /// Devolucao de compra para comercializacao (loja → fornecedor), interestadual.
  static const String cfopDevolucaoCompraInterestadual = '6202';

  /// Devolucao de compra estadual com mercadoria sujeita a ST.
  static const String cfopDevolucaoCompraEstadualSt = '5411';

  /// Devolucao de compra interestadual com mercadoria sujeita a ST.
  static const String cfopDevolucaoCompraInterestadualSt = '6411';

  /// Origem da mercadoria padrao (0 = nacional) quando o produto nao informar.
  static const String icmsOrigemPadrao = '0';

  /// CST ICMS padrao no balcao (Regime Normal): 00 = tributada integralmente.
  static const String icmsSituacaoTributariaPadrao = '00';

  /// CSOSN padrao (Simples Nacional): 102 — tributada SN sem credito.
  /// Validar com o contador da loja (102, 103, 500, etc.).
  static const String icmsSituacaoTributariaSimples = '102';

  /// PIS/COFINS padrao (Regime Normal): 01 = operacao tributavel, aliquota basica.
  static const String pisCofinsSituacaoTributariaPadrao = '01';

  /// PIS/COFINS padrao (Simples): 49 = outras saidas.
  static const String pisCofinsSituacaoTributariaSimples = '49';

  /// CST IBS/CBS padrao (tributacao integral). NT 2025.002 / guia Focus.
  static const String ibsCbsSituacaoTributariaPadrao = '000';

  /// cClassTrib padrao (tributado integralmente IBS e CBS).
  static const String ibsCbsClassificacaoTributariaPadrao = '000001';

  /// Natureza da operacao padrao (NFC-e e NF-e).
  static const String naturezaOperacaoPadrao = 'Venda de mercadoria';

  /// Natureza da operacao NFC-e (balcao). Se vazio, usa [naturezaOperacaoPadrao].
  static const String naturezaOperacaoNfce = 'Venda de mercadoria';

  /// Natureza da operacao NF-e modelo 55.
  static const String naturezaOperacaoNfe = 'Venda de mercadoria';

  /// Codigo de Seguranca do Contribuinte (CSC) — SEFAZ-BA (NFC-e local).
  /// Focus NFe costuma gerenciar CSC no painel; deixe vazio se usar so Focus.
  static const String csc = '';

  /// ID do CSC (1 a 999999).
  static const String idCsc = '';

  /// UF do emitente (loja na Bahia).
  static const String ufEmitente = 'BA';

  /// Ambiente: `homologacao` | `producao`.
  static const String ambiente = 'homologacao';

  static bool get configurado =>
      apiBaseUrl.trim().isNotEmpty &&
      apiToken.trim().isNotEmpty &&
      !apiToken.contains('SEU_TOKEN') &&
      cnpjEmitente.trim().length == 14 &&
      cnpjEmitente != '00000000000000' &&
      inscricaoEstadualEmitente.replaceAll(RegExp(r'\D'), '').isNotEmpty;

  static String get endpointEmitirNfce {
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/nfce';
  }
}

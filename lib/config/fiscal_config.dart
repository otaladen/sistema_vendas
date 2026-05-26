/// Credenciais e endpoints da API fiscal (Focus NFe — NFC-e / NF-e).
///
/// **Antes de emitir no caixa:** preencha [apiToken], [cnpjEmitente] e
/// [inscricaoEstadualEmitente] conforme o cadastro da empresa na Focus.
/// Nao commitar token real em repositorio publico.
class FiscalConfig {
  const FiscalConfig._();

  /// URL base da API Focus NFe.
  ///
  /// Homologacao: notas de teste, sem validade juridica.
  /// Producao: altere para `https://api.focusnfe.com.br` e [ambiente] = `producao`.
  static const String apiBaseUrl = 'https://homologacao.focusnfe.com.br';

  /// Token do painel Focus (autenticacao HTTP Basic: `token:`).
  static const String apiToken = 'rLVoesq3fNQEubxSRwTDH4laV1wPfNOb';

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

  /// Origem da mercadoria padrao (0 = nacional) quando o produto nao informar.
  static const String icmsOrigemPadrao = '0';

  /// CST ICMS padrao no balcao (Regime Normal): 00 = tributada integralmente.
  static const String icmsSituacaoTributariaPadrao = '00';

  /// PIS/COFINS padrao (Regime Normal): 01 = operacao tributavel, aliquota basica.
  static const String pisCofinsSituacaoTributariaPadrao = '01';

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

/// Credenciais e endpoints da API fiscal (NFC-e Bahia).
///
/// Preencha com o contador / provedor (Focus, Webmania, Nuvem Fiscal, etc.).
/// Nao commitar valores reais em repositorio publico.
class FiscalConfig {
  const FiscalConfig._();

  /// URL base da API (ex.: https://api.provedor.com.br/v2).
  static const String apiBaseUrl = '';

  /// Token ou API Key do provedor.
  static const String apiToken = '';

  /// CNPJ da loja emitente (somente digitos).
  static const String cnpjEmitente = '';

  /// Codigo de Seguranca do Contribuinte (CSC) — SEFAZ.
  static const String csc = '';

  /// ID do CSC (1 a 999999).
  static const String idCsc = '';

  /// UF do emitente (loja na Bahia).
  static const String ufEmitente = 'BA';

  /// Ambiente: homologacao | producao.
  static const String ambiente = 'homologacao';

  static bool get configurado =>
      apiBaseUrl.trim().isNotEmpty &&
      apiToken.trim().isNotEmpty &&
      cnpjEmitente.trim().length == 14;

  static String get endpointEmitirNfce {
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/nfce';
  }
}

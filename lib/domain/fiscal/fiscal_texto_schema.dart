/// Limites de texto do schema XML NF-e/NFC-e (SEFAZ / Focus).
///
/// O cadastro do cliente pode guardar valores maiores; no envio os campos
/// devem ser cortados para nao rejeitar a nota (ex.: logradouro > 60).
abstract final class FiscalTextoSchema {
  FiscalTextoSchema._();

  static const int nomeMax = 60;
  static const int logradouroMax = 60;
  static const int numeroMax = 60;
  static const int complementoMax = 60;
  static const int bairroMax = 60;
  static const int municipioMax = 60;

  /// Trim + corta em [max] caracteres (schema TString).
  static String limitar(String value, int max) {
    final t = value.trim();
    if (max <= 0 || t.length <= max) return t;
    return t.substring(0, max).trimRight();
  }

  static String nome(String value) => limitar(value, nomeMax);

  static String logradouro(String value) => limitar(value, logradouroMax);

  static String numero(String value) => limitar(value, numeroMax);

  static String complemento(String value) => limitar(value, complementoMax);

  static String bairro(String value) => limitar(value, bairroMax);

  static String municipio(String value) => limitar(value, municipioMax);
}

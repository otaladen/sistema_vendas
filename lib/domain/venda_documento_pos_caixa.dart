import '../model/venda.dart';

/// Documento obrigatorio apos pagamento no caixa (cupom interno ou nota fiscal).
abstract final class VendaDocumentoPosCaixa {
  VendaDocumentoPosCaixa._();

  /// Verdadeiro quando a venda ja tem cupom interno, NFC-e ou NF-e 55 autorizada.
  static bool registrado(
    Venda venda, {
    required bool temNfe55Autorizada,
  }) {
    if (venda.estoqueBaixadoCupom) return true;
    if (venda.nfceEmitida) return true;
    if (temNfe55Autorizada) return true;
    return false;
  }
}

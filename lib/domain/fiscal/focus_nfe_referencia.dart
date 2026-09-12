/// Referencia Focus da NFC-e/NF-e (`venda_834`, `venda_834_nfe`).
abstract final class FocusNfeReferencia {
  FocusNfeReferencia._();

  static final RegExp _idVenda = RegExp(r'^venda_(\d+)(?:_|$)');

  /// Extrai o id local de `venda_834`, `venda_834_nfe` ou `venda_834_nfce`.
  static int? idVenda(String referencia) {
    final m = _idVenda.firstMatch(referencia.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}

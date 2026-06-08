import '../../model/venda.dart';

/// Uma venda finalizada deve ter no maximo um documento fiscal de saida (NFC-e ou NF-e 55).
abstract final class VendaDocumentoFiscalMutex {
  VendaDocumentoFiscalMutex._();

  static bool bloqueiaNovaNfce(Venda venda) =>
      mensagemBloqueioNovaNfce(venda) != null;

  static bool bloqueiaNovaNfe55(Venda venda) =>
      mensagemBloqueioNovaNfe55(venda) != null;

  static String? mensagemBloqueioNovaNfce(Venda venda) {
    if (venda.nfceEmitida) {
      return 'NFC-e ja consta emitida para esta venda.';
    }
    if (venda.nfe55Autorizada) {
      return 'Nao e permitido emitir NFC-e quando ja existe NF-e modelo 55 '
          'autorizada nesta venda.';
    }
    if (venda.nfe55Processando) {
      return 'NF-e em processamento nesta venda. Aguarde o retorno da SEFAZ '
          'antes de emitir NFC-e.';
    }
    return null;
  }

  static String? mensagemBloqueioNovaNfe55(Venda venda) {
    if (venda.nfceEmitida) {
      return 'Nao e permitido emitir NF-e modelo 55 quando ja existe NFC-e '
          'autorizada nesta venda.';
    }
    if (venda.nfceProcessandoPendenteFocus || venda.nfceEmissaoEmAndamento) {
      return 'NFC-e em processamento nesta venda. Aguarde o retorno da SEFAZ '
          'antes de emitir NF-e.';
    }
    return null;
  }
}

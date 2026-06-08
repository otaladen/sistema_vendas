/// Normaliza URLs de DANFE/XML retornadas pela API Focus NFe.
class FocusDocumentoFiscalUrl {
  FocusDocumentoFiscalUrl._();

  /// Converte caminho relativo (`/v2/nfce/...`) em URL absoluta com [apiBaseUrl].
  static String normalizar(String url, {required String apiBaseUrl}) {
    var t = url.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('//')) return 'https:$t';
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return t;
    if (t.startsWith('/')) return '$base$t';
    return '$base/$t';
  }

  static bool urlAbsolutaValida(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// PDF da Focus costuma exigir token HTTP Basic (nao abre no navegador).
  static bool provavelmenteRequerAutenticacaoFocus(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    if (!u.contains('focusnfe.com.br')) return false;
    return u.contains('/v2/') ||
        u.endsWith('.pdf') ||
        u.contains('/danfe') ||
        u.contains('caminho_danfe');
  }
}

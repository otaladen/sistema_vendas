/// Monta a URL da API de negocio do PC servidor (Terminal Leve).
abstract final class LanApiUrl {
  static const portaPadrao = 8788;

  /// Normaliza qualquer URL/IP para a API em [portaApi] (padrao :8788).
  ///
  /// Aceita `192.168.0.10`, `http://192.168.0.10`, `100.64.1.2:8788`, etc.
  /// Se a porta for omitida, adiciona [:8788]. Em terminal leve a porta da
  /// API e sempre [portaApi] (forcada), para evitar digitar errado no celular.
  static String fromSyncUrl(String syncUrl, {int portaApi = portaPadrao}) {
    final raw = syncUrl.trim();
    if (raw.isEmpty) return '';
    var s = raw;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return '';
    return Uri(
      scheme: u.scheme.isEmpty ? 'http' : u.scheme,
      host: u.host,
      port: portaApi,
    ).toString();
  }

  static String local(int portaApi) => 'http://127.0.0.1:$portaApi';
}

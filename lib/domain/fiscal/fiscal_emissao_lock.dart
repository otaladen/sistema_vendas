import '../../model/venda.dart';

/// Lock de emissao fiscal na venda (campos sincronizados na LAN — F6).
abstract final class FiscalEmissaoLock {
  FiscalEmissaoLock._();

  static const duracaoMaxima = Duration(minutes: 3);
  static const statusEmAndamento = 'emissao_em_andamento';
  static const _prefixo = 'emissao_lock:';

  static String marcador(String deviceId, String referencia) {
    final dev = deviceId.trim();
    final ref = referencia.trim();
    return '$_prefixo$dev:${DateTime.now().toUtc().millisecondsSinceEpoch}:$ref';
  }

  static bool ehMarcadorEmissao(String protocolo) =>
      protocolo.trim().startsWith(_prefixo);

  static bool nfceBloqueadaPorOutroDispositivo(Venda venda, String deviceIdAtual) =>
      bloqueadaPorOutroDispositivo(
        statusFocus: venda.nfceStatusFocus,
        protocolo: venda.nfceProtocolo,
        deviceIdAtual: deviceIdAtual,
      );

  static bool nfeBloqueadaPorOutroDispositivo(Venda venda, String deviceIdAtual) =>
      bloqueadaPorOutroDispositivo(
        statusFocus: venda.nfeStatusFocus,
        protocolo: venda.nfeProtocolo,
        deviceIdAtual: deviceIdAtual,
      );

  static bool bloqueadaPorOutroDispositivo({
    required String statusFocus,
    required String protocolo,
    required String deviceIdAtual,
  }) {
    if (statusFocus.trim() != statusEmAndamento) return false;
    final parsed = _parseMarcador(protocolo);
    if (parsed == null) return false;
    if (parsed.deviceId == deviceIdAtual.trim()) return false;
    final idadeMs =
        DateTime.now().toUtc().millisecondsSinceEpoch - parsed.timestampMs;
    if (idadeMs > duracaoMaxima.inMilliseconds) return false;
    return true;
  }

  static ({String deviceId, int timestampMs})? _parseMarcador(String protocolo) {
    final raw = protocolo.trim();
    if (!raw.startsWith(_prefixo)) return null;
    final resto = raw.substring(_prefixo.length);
    final partes = resto.split(':');
    if (partes.length < 2) return null;
    final deviceId = partes.first.trim();
    final ts = int.tryParse(partes[1]) ?? 0;
    if (deviceId.isEmpty || ts <= 0) return null;
    return (deviceId: deviceId, timestampMs: ts);
  }
}

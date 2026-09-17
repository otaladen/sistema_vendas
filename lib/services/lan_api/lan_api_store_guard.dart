/// Resposta 503 enquanto o ObjectBox do PC servidor esta fechado para backup.
abstract final class LanApiStoreGuard {
  LanApiStoreGuard._();

  static const code = 'store_unavailable';
  static const mensagem =
      'Servidor em backup momentaneo. Tente novamente em instantes.';

  static bool caminhoLivreDuranteBackup(String path) {
    final p = path.toLowerCase();
    return p == 'api/health' ||
        p.endsWith('/api/health') ||
        p == 'api/presence' ||
        p.endsWith('/api/presence') ||
        p == 'api/stream' ||
        p.endsWith('/api/stream');
  }

  static bool erroStoreFechada(Object erro) {
    return erro.toString().toLowerCase().contains('store is closed');
  }

  static Map<String, dynamic> bodyJson() => {
        'ok': false,
        'error': mensagem,
        'code': code,
      };
}

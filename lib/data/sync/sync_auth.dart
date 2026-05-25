/// Cabecalho e query usados na autenticacao do sync LAN.
abstract final class SyncAuth {
  static const headerName = 'x-sync-token';
  static const queryParam = 'token';
}

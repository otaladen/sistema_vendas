import '../app_config_repository.dart';

/// Preferencias locais (nao replicadas na LAN) para reduzir sync storm na implantacao.
class SyncImplantacaoConfig {
  SyncImplantacaoConfig(this._repository);

  final AppConfigRepository _repository;

  static const intervaloSyncNormal = Duration(seconds: 90);
  static const intervaloSyncImplantacao = Duration(seconds: 120);
  /// Agrupa varias gravações locais de prioridade media numa unica sync.
  static const debounceRedeNormal = Duration(seconds: 3);
  static const debounceRedeImplantacao = Duration(seconds: 6);
  /// Venda/estoque: curto o bastante para coalescer, longo o bastante
  /// para o dirty do SharedPreferences ja estar gravado.
  static const debouncePrioritario = Duration(milliseconds: 250);

  Future<bool> modoImplantacaoAtivo() =>
      _repository.carregarModoImplantacaoLocal();

  Future<Duration> intervaloSyncPeriodico() async {
    final implantacao = await modoImplantacaoAtivo();
    return implantacao ? intervaloSyncImplantacao : intervaloSyncNormal;
  }

  Future<Duration> debounceEventoRede() async {
    final implantacao = await modoImplantacaoAtivo();
    return implantacao ? debounceRedeImplantacao : debounceRedeNormal;
  }
}

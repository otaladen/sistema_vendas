import '../app_config_repository.dart';

/// Preferencias locais (nao replicadas na LAN) para reduzir sync storm na implantacao.
class SyncImplantacaoConfig {
  SyncImplantacaoConfig(this._repository);

  final AppConfigRepository _repository;

  static const intervaloSyncNormal = Duration(seconds: 30);
  static const intervaloSyncImplantacao = Duration(seconds: 60);
  static const debounceRedeNormal = Duration(milliseconds: 100);
  static const debounceRedeImplantacao = Duration(seconds: 3);

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

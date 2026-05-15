import 'package:flutter/foundation.dart';

/// Sinal global apos pull de dados da rede (telas podem escutar e recarregar).
class SyncRefreshHub extends ChangeNotifier {
  SyncRefreshHub._();
  static final SyncRefreshHub instance = SyncRefreshHub._();

  void notificarDadosAtualizados() {
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';

/// Sinal no processo do PC servidor quando entrega/venda logistica muda via LanApi.
/// A UI do PC1 escuta e recarrega a lista sem depender do SyncRefreshHub antigo.
class EntregaLocalRefreshHub extends ChangeNotifier {
  EntregaLocalRefreshHub._();
  static final EntregaLocalRefreshHub instance = EntregaLocalRefreshHub._();

  void notificar() {
    notifyListeners();
  }
}

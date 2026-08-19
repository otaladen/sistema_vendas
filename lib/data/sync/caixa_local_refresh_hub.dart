import 'package:flutter/foundation.dart';

/// Sinal no processo do PC servidor quando a sessao de caixa muda via LanApi
/// (abrir/fechar/suprimento). A UI do Caixa no PC1 escuta e recarrega.
class CaixaLocalRefreshHub extends ChangeNotifier {
  CaixaLocalRefreshHub._();
  static final CaixaLocalRefreshHub instance = CaixaLocalRefreshHub._();

  void notificar() => notifyListeners();
}

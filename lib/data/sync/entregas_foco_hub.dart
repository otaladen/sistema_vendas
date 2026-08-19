import 'package:flutter/foundation.dart';

/// Pede para a aba Entregas filtrar um numero de pedido (atalho do chat).
class EntregasFocoHub extends ChangeNotifier {
  EntregasFocoHub._();
  static final instance = EntregasFocoHub._();

  int? _numeroPedido;
  int _epoch = 0;

  int? get numeroPedido => _numeroPedido;
  int get epoch => _epoch;

  void focarPedido(int numero) {
    if (numero <= 0) return;
    _numeroPedido = numero;
    _epoch++;
    notifyListeners();
  }

  void consumir() {
    _numeroPedido = null;
  }
}

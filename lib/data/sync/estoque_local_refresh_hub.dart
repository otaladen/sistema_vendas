import 'package:flutter/foundation.dart';

/// Sinal no processo do PC servidor quando estoque/produto muda via LanApi
/// (ex.: terminal finalizou venda). A UI do PC1 escuta e sincroniza o cache
/// do [ProdutoRepository] da shell com o ObjectBox ja atualizado.
class EstoqueLocalRefreshHub extends ChangeNotifier {
  EstoqueLocalRefreshHub._();
  static final EstoqueLocalRefreshHub instance = EstoqueLocalRefreshHub._();

  List<int> _ultimaIds = const [];
  List<int> get ultimaIds => _ultimaIds;

  void notificar({List<int>? ids}) {
    _ultimaIds = ids ?? const [];
    notifyListeners();
  }
}

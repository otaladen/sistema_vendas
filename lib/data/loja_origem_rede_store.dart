import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entregas/loja_origem_mercadoria.dart';

/// Nomes de lojas/depositos usados em cross-docking (alem do Deposito Central).
class LojaOrigemRedeStore {
  static const _k = 'lojas_origem_rede_v1';

  Future<List<String>> listar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getStringList(_k)
        ?.map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList() ??
        const [];
  }

  Future<void> lembrar(String nome) async {
    final n = nome.trim();
    if (n.isEmpty) return;
    if (LojaOrigemMercadoria.ehLocal(n) || LojaOrigemMercadoria.ehMisto(n)) {
      return;
    }
    final atuais = await listar();
    final key = n.toLowerCase();
    final next = [
      n,
      ...atuais.where((e) => e.toLowerCase() != key),
    ];
    if (next.length > 20) {
      next.removeRange(20, next.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_k, next);
  }
}

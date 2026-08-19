import 'package:flutter/foundation.dart';

import '../../domain/usuario_senha_codec.dart';
import '../../model/vendedor.dart';
import '../sync/sync_entity_codec.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

class VendedorApiRepository extends ChangeNotifier {
  VendedorApiRepository(this._client);

  final LanApiClient _client;
  List<Vendedor> _lista = [];

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  Future<void> hidratar() async {
    _exigirServidorOnline();
    _lista = await _client.listarVendedores();
    notifyListeners();
  }

  List<Vendedor> listarTodos() => List.unmodifiable(_lista);
  List<Vendedor> listarAtivos() =>
      _lista.where((v) => v.ativo).toList(growable: false);

  Vendedor? obterPorId(int id) {
    for (final v in _lista) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<Vendedor> pesquisar(String termo) {
    if (_offline) return const [];
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return listarTodos();
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    return _lista.where((v) {
      final campos = [
        v.codigoInterno,
        v.nomeCompleto,
        v.apelido,
        v.telefone,
        v.whatsapp,
        v.email,
      ].map((e) => e.toLowerCase());
      if (campos.any((c) => c.contains(t))) return true;
      if (digitos.isEmpty) return false;
      final nums = [v.telefone, v.whatsapp, v.codigoInterno]
          .map((s) => s.replaceAll(RegExp(r'\D'), ''));
      return nums.any((n) => n.contains(digitos));
    }).toList();
  }

  Future<int> salvarRemoto(Vendedor v) async {
    _exigirServidorOnline();
    final id = await _client.salvarVendedor({
      'vendedor': SyncEntityCodec.vendedorParaMap(v),
    });
    await hidratar();
    return id;
  }

  int salvar(Vendedor v) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  bool remover(int id) {
    throw StateError(
      'Terminal leve: use removerRemoto (async) no cadastro de vendedores.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerVendedor(id);
    if (ok) {
      _lista = _lista.where((v) => v.id != id).toList(growable: false);
      notifyListeners();
    }
    return ok;
  }

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final v in _lista) {
      if (v.id != ignorarId && v.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }

  bool temSenhaPdvConfigurada(Vendedor vendedor) =>
      vendedor.senhaPdv.trim().isNotEmpty;

  int contarAtivosComSenhaPdv() =>
      listarAtivos().where(temSenhaPdvConfigurada).length;

  /// Validacao no cache hidratado (mesma regra do ObjectBox local).
  Vendedor? autenticarPorSenhaPdv(String senhaPlain) {
    final senha = senhaPlain.trim();
    if (senha.isEmpty) return null;

    Vendedor? unico;
    for (final v in listarAtivos()) {
      if (!temSenhaPdvConfigurada(v)) continue;
      if (!UsuarioSenhaCodec.verificar(senha, v.senhaPdv)) continue;
      if (unico != null) return null;
      unico = v;
    }
    return unico;
  }

  /// Validacao autoritativa no PC servidor (`POST /api/vendedores/autenticar-pin`).
  ///
  /// Se a rota nao existir (servidor antigo), cai no cache hidratado.
  Future<Vendedor?> autenticarPorSenhaPdvRemoto(String senhaPlain) async {
    _exigirServidorOnline();
    final senha = senhaPlain.trim();
    if (senha.isEmpty) return null;
    try {
      final v = await _client.autenticarVendedorPin(senha);
      if (v != null) {
        final i = _lista.indexWhere((e) => e.id == v.id);
        if (i >= 0) {
          _lista[i] = v;
        } else {
          _lista = [..._lista, v];
        }
        notifyListeners();
      }
      return v;
    } on LanApiException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('404') || m.contains('route not found')) {
        return autenticarPorSenhaPdv(senha);
      }
      rethrow;
    }
  }

  static int? codigoInternoComoInteiro(String codigoInterno) {
    final t = codigoInterno.trim();
    if (t.isEmpty) return null;
    final direto = int.tryParse(t);
    if (direto != null) return direto;
    final m = RegExp(r'\d+').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  int proximoCodigoInternoSequencial() {
    var maxN = 0;
    for (final v in _lista) {
      final n = codigoInternoComoInteiro(v.codigoInterno);
      if (n != null && n > maxN) maxN = n;
    }
    return maxN + 1;
  }
}

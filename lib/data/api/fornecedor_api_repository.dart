import 'package:flutter/foundation.dart';

import '../../model/fornecedor_nfe.dart';
import '../fornecedor_repository.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

/// Cadastro de fornecedores no Terminal Leve (HTTP → PC1).
class FornecedorApiRepository extends ChangeNotifier {
  FornecedorApiRepository(this._client);

  final LanApiClient _client;
  final Map<int, FornecedorNfe> _porId = {};
  List<FornecedorNfe> _lista = [];

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  void _mesclarNaCache(Iterable<FornecedorNfe> items) {
    for (final f in items) {
      if (f.id <= 0) continue;
      _porId[f.id] = f;
    }
    final todos = _porId.values.toList()
      ..sort(
        (a, b) => a.nomeExibicao.toLowerCase().compareTo(
              b.nomeExibicao.toLowerCase(),
            ),
      );
    _lista = todos;
  }

  Future<void> hidratar({String q = '', bool apenasAtivos = false}) async {
    _exigirServidorOnline();
    final items = await _client.listarFornecedores(
      q: q,
      limit: 500,
      apenasAtivos: apenasAtivos,
    );
    if (q.trim().isEmpty) {
      _lista = items;
      _porId
        ..clear()
        ..addEntries(items.map((f) => MapEntry(f.id, f)));
    } else {
      _mesclarNaCache(items);
    }
    notifyListeners();
  }

  FornecedorNfe? obterPorId(int id) => _porId[id];

  Future<FornecedorNfe?> obterPorIdRemoto(int id) async {
    if (id <= 0) return null;
    _exigirServidorOnline();
    final f = await _client.obterFornecedor(id);
    if (f != null) {
      _porId[f.id] = f;
      _mesclarNaCache([f]);
      notifyListeners();
    }
    return f;
  }

  FornecedorNfe? obterPorCnpj(String cnpjOuDoc) {
    final dig = FornecedorRepository.somenteDigitos(cnpjOuDoc);
    if (dig.isEmpty) return null;
    for (final f in _lista) {
      if (FornecedorRepository.somenteDigitos(f.cnpj) == dig) return f;
      if (f.cnpj == cnpjOuDoc.trim()) return f;
    }
    return null;
  }

  List<FornecedorNfe> listarTodos({bool apenasAtivos = false}) {
    if (_offline) return const [];
    if (!apenasAtivos) return List.unmodifiable(_lista);
    return _lista.where((f) => f.ativo).toList(growable: false);
  }

  List<FornecedorNfe> pesquisar(String termo, {bool apenasAtivos = false}) {
    if (_offline) return const [];
    final t = termo.trim().toLowerCase();
    final dig = FornecedorRepository.somenteDigitos(termo);
    final base = listarTodos(apenasAtivos: apenasAtivos);
    if (t.isEmpty && dig.isEmpty) return base;
    return base.where((f) {
      if (t.isNotEmpty) {
        final campos = [
          f.razaoSocial,
          f.nomeFantasia,
          f.cidade,
          f.email,
          f.telefone,
          f.whatsapp,
        ].map((e) => e.toLowerCase());
        if (campos.any((c) => c.contains(t))) return true;
      }
      if (dig.isNotEmpty) {
        final docs = [
          FornecedorRepository.somenteDigitos(f.cnpj),
          FornecedorRepository.somenteDigitos(f.telefone),
          FornecedorRepository.somenteDigitos(f.whatsapp),
          FornecedorRepository.somenteDigitos(f.cep),
        ];
        if (docs.any((d) => d.contains(dig))) return true;
      }
      return false;
    }).toList();
  }

  Future<List<FornecedorNfe>> pesquisarRemoto(
    String termo, {
    int limit = 100,
    bool apenasAtivos = false,
  }) async {
    _exigirServidorOnline();
    final t = termo.trim();
    if (t.isEmpty) {
      return listarTodos(apenasAtivos: apenasAtivos).take(limit).toList();
    }
    final items = await _client.listarFornecedores(
      q: t,
      limit: limit,
      apenasAtivos: apenasAtivos,
    );
    _mesclarNaCache(items);
    notifyListeners();
    final locais = pesquisar(t, apenasAtivos: apenasAtivos);
    final ids = <int>{};
    final out = <FornecedorNfe>[];
    for (final f in [...items, ...locais]) {
      if (ids.add(f.id)) out.add(f);
      if (out.length >= limit) break;
    }
    return out;
  }

  int salvar(FornecedorNfe fornecedor) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  Future<int> salvarRemoto(FornecedorNfe fornecedor) async {
    _exigirServidorOnline();
    final id = await _client.salvarFornecedor(fornecedor);
    final fresco = await _client.obterFornecedor(id);
    if (fresco != null) {
      _porId[fresco.id] = fresco;
      _mesclarNaCache([fresco]);
    }
    try {
      await hidratar();
      if (fresco != null) {
        _porId[fresco.id] = fresco;
        if (!_lista.any((f) => f.id == fresco.id)) {
          _lista = [..._lista, fresco];
        }
      }
    } catch (_) {
      // Mantem o fresco ja mesclado.
    }
    notifyListeners();
    return id;
  }

  bool remover(int id) {
    throw StateError(
      'Terminal leve: use removerRemoto (async) no cadastro de fornecedores.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerFornecedor(id);
    if (ok) {
      _porId.remove(id);
      _lista.removeWhere((f) => f.id == id);
      notifyListeners();
    }
    return ok;
  }
}

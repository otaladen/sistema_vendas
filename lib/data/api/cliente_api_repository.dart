import 'package:flutter/foundation.dart';

import '../../model/cliente.dart';
import 'lan_api_client.dart';
import 'lan_api_event_hub.dart';

class ClienteApiRepository extends ChangeNotifier {
  ClienteApiRepository(this._client);

  final LanApiClient _client;
  final Map<int, Cliente> _porId = {};
  List<Cliente> _lista = [];

  bool get _offline => LanApiEventHub.instance.deveBloquearOperacoes;

  void _exigirServidorOnline() {
    if (_offline) {
      throw LanApiException(LanApiEventHub.msgServidorOffline);
    }
  }

  static String _somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  void _mesclarNaCache(Iterable<Cliente> items) {
    for (final c in items) {
      if (c.id <= 0) continue;
      _porId[c.id] = c;
    }
    // Mantem ordem por nome; inclui todos os conhecidos.
    final todos = _porId.values.toList()
      ..sort(
        (a, b) => a.nomeRazao.toLowerCase().compareTo(b.nomeRazao.toLowerCase()),
      );
    _lista = todos;
  }

  Future<void> hidratar({String q = ''}) async {
    _exigirServidorOnline();
    final items = await _client.listarClientes(q: q, limit: 500);
    if (q.trim().isEmpty) {
      _lista = items;
      _porId
        ..clear()
        ..addEntries(items.map((c) => MapEntry(c.id, c)));
    } else {
      _mesclarNaCache(items);
    }
    notifyListeners();
  }

  Cliente? obterPorId(int id) => _porId[id];

  /// Relê o cliente no PC1 e atualiza o cache (bloqueio/limite frescos).
  Future<Cliente?> obterPorIdRemoto(int id) async {
    if (id <= 0) return null;
    _exigirServidorOnline();
    final c = await _client.obterCliente(id);
    if (c != null) {
      _porId[c.id] = c;
      final i = _lista.indexWhere((e) => e.id == c.id);
      if (i >= 0) {
        _lista[i] = c;
      } else {
        _lista = [..._lista, c];
      }
      notifyListeners();
    }
    return c;
  }

  /// Atualiza campos de credito/bloqueio vindos de `/api/titulos/saldo-cliente`.
  void aplicarResumoCredito({
    required int clienteId,
    double? limiteCredito,
    bool? bloqueadoFiado,
    String? motivoBloqueio,
  }) {
    final c = _porId[clienteId];
    if (c == null) return;
    var mudou = false;
    if (limiteCredito != null && c.limiteCredito != limiteCredito) {
      c.limiteCredito = limiteCredito;
      mudou = true;
    }
    if (bloqueadoFiado != null && c.bloqueadoFiado != bloqueadoFiado) {
      c.bloqueadoFiado = bloqueadoFiado;
      mudou = true;
    }
    if (motivoBloqueio != null && c.motivoBloqueio != motivoBloqueio) {
      c.motivoBloqueio = motivoBloqueio;
      mudou = true;
    }
    if (mudou) notifyListeners();
  }

  List<Cliente> listarTodos() => List.unmodifiable(_lista);

  List<Cliente> listarPaginado({
    int offset = 0,
    int limit = 80,
    bool somenteAtivos = false,
  }) {
    if (_offline) return const [];
    var base = _lista;
    if (somenteAtivos) base = base.where((c) => c.ativo).toList();
    if (offset >= base.length) return const [];
    final end = (offset + limit).clamp(0, base.length);
    return base.sublist(offset, end);
  }

  /// Filtro no cache hidratado (nome, documento com/sem mascara, telefone).
  List<Cliente> pesquisar(String termo) {
    if (_offline) return const [];
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return listarPaginado(limit: 80);
    final digitos = _somenteDigitos(termo);
    return _lista.where((c) {
      final campos = [
        c.nomeRazao,
        c.nomeFantasia,
        c.documento,
        c.telefone,
        c.whatsapp,
        c.email,
        c.cidade,
        c.codigoInterno,
      ].map((e) => e.toLowerCase());
      if (campos.any((campo) => campo.contains(t))) return true;
      if (digitos.isEmpty) return false;
      final nums = [
        c.documento,
        c.telefone,
        c.whatsapp,
        c.cep,
      ].map(_somenteDigitos);
      return nums.any((n) => n.contains(digitos));
    }).toList();
  }

  /// Busca no PC1 (`GET /api/clientes?q=`) e mescla no cache.
  Future<List<Cliente>> pesquisarRemoto(String termo, {int limit = 80}) async {
    _exigirServidorOnline();
    final t = termo.trim();
    if (t.isEmpty) {
      return listarPaginado(limit: limit);
    }
    final items = await _client.listarClientes(q: t, limit: limit);
    _mesclarNaCache(items);
    // Reforça match por digitos (CPF/CNPJ) no cache mesclado.
    final locais = pesquisar(t);
    notifyListeners();
    if (locais.length >= items.length) return locais.take(limit).toList();
    // Une remotos + locais digit-match sem duplicar.
    final ids = <int>{};
    final out = <Cliente>[];
    for (final c in [...items, ...locais]) {
      if (ids.add(c.id)) out.add(c);
      if (out.length >= limit) break;
    }
    return out;
  }

  int salvar(Cliente cliente) {
    throw StateError('Use salvarRemoto() no terminal leve.');
  }

  Future<int> salvarRemoto(Cliente cliente) async {
    _exigirServidorOnline();
    final id = await _client.salvarCliente(cliente);
    // Garante o registro salvo no cache mesmo se a lista paginada (500) nao o cobrir.
    final fresco = await _client.obterCliente(id);
    if (fresco != null) {
      _porId[fresco.id] = fresco;
      _mesclarNaCache([fresco]);
    }
    try {
      final items = await _client.listarClientes(limit: 500);
      _lista = items;
      for (final c in items) {
        _porId[c.id] = c;
      }
      if (fresco != null) {
        _porId[fresco.id] = fresco;
        if (!_lista.any((c) => c.id == fresco.id)) {
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
      'Terminal leve: use removerRemoto (async) no cadastro de clientes.',
    );
  }

  Future<bool> removerRemoto(int id) async {
    _exigirServidorOnline();
    final ok = await _client.removerCliente(id);
    if (ok) {
      _porId.remove(id);
      _lista.removeWhere((c) => c.id == id);
      notifyListeners();
    }
    return ok;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/caixa_sessao.dart';
import 'sync/sync_write_trigger.dart';

/// Persistencia local + pacote para sincronizacao LAN de sessoes de caixa.
///
/// Escritas serializadas para evitar lost update em [SharedPreferences].
class CaixaSessaoRepository {
  static const _kTerminalId = 'caixa_terminal_id_v1';
  static const _kSessoesRede = 'caixa_sessoes_rede_v1';
  static const _kLegadoSessao = 'caixa_sessao_atual_v1';

  static Future<void> _mutex = Future<void>.value();

  static Future<T> _serializar<T>(Future<T> Function() acao) async {
    final anterior = _mutex;
    final liberado = Completer<void>();
    _mutex = liberado.future;
    await anterior;
    try {
      return await acao();
    } finally {
      liberado.complete();
    }
  }

  Future<String> obterTerminalId() async {
    return _serializar(_obterTerminalIdInterno);
  }

  Future<String> _obterTerminalIdInterno() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kTerminalId)?.trim() ?? '';
    if (id.isNotEmpty) return id;
    var host = '';
    try {
      host = Platform.localHostname.trim();
    } catch (_) {
      host = '';
    }
    id = host.isNotEmpty
        ? 'pc_$host'
        : 'terminal_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_kTerminalId, id);
    return id;
  }

  Future<Map<String, CaixaSessao>> listarTodasSessoes({bool migrarLegado = true}) async {
    return _serializar(() => _listarTodasSessoesInterno(migrarLegado: migrarLegado));
  }

  Future<Map<String, CaixaSessao>> _listarTodasSessoesInterno({
    bool migrarLegado = true,
  }) async {
    if (migrarLegado) {
      await _migrarLegadoSeNecessario();
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSessoesRede);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, CaixaSessao>{};
      for (final e in decoded.entries) {
        if (e.value is Map) {
          final m = Map<String, dynamic>.from(e.value as Map);
          final s = CaixaSessao.fromMap(m);
          if (s.terminalId.isNotEmpty) {
            out[s.terminalId] = s;
          }
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<CaixaSessao> carregarSessaoLocal() async {
    final terminalId = await obterTerminalId();
    final todas = await listarTodasSessoes();
    return todas[terminalId] ?? CaixaSessao.vazia(terminalId);
  }

  Future<void> salvarSessaoLocal(CaixaSessao sessao, {bool propagarRede = true}) async {
    await _serializar(() async {
      final todas = await _listarTodasSessoesInterno(migrarLegado: false);
      final terminalId = sessao.terminalId.isNotEmpty
          ? sessao.terminalId
          : await _obterTerminalIdInterno();
      final atualizado = sessao.copyWith(
        terminalId: terminalId,
        atualizadoEm: DateTime.now(),
      );
      todas[terminalId] = atualizado;
      await _persistirMapa(todas);
      if (propagarRede) {
        notificarAlteracaoParaRede(
          entidade: 'caixa_sessoes',
          entidadeId: 1,
        );
      }
    });
  }

  Future<void> aplicarPacoteRede(Map<String, dynamic> payload) async {
    await _serializar(() async {
      final remotas = _mapaDePayload(payload);
      final locais = await _listarTodasSessoesInterno(migrarLegado: false);
      for (final entry in remotas.entries) {
        final remota = entry.value;
        final local = locais[entry.key];
        if (local == null) {
          locais[entry.key] = remota;
          continue;
        }
        final tLocal = local.atualizadoEm?.millisecondsSinceEpoch ?? 0;
        final tRemota = remota.atualizadoEm?.millisecondsSinceEpoch ?? 0;
        if (tRemota >= tLocal) {
          locais[entry.key] = remota;
        }
      }
      await _persistirMapa(locais);
    });
  }

  static Map<String, dynamic> pacoteParaSync(Map<String, CaixaSessao> mapa) {
    return {
      'terminais': mapa.map((k, v) => MapEntry(k, v.toMap())),
    };
  }

  static Map<String, CaixaSessao> _mapaDePayload(Map<String, dynamic> payload) {
    final raw = payload['terminais'];
    if (raw is! Map) return {};
    final out = <String, CaixaSessao>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        final m = Map<String, dynamic>.from(e.value as Map);
        final s = CaixaSessao.fromMap(m);
        final id = s.terminalId.isNotEmpty ? s.terminalId : e.key.toString();
        out[id] = s.copyWith(terminalId: id);
      }
    }
    return out;
  }

  Future<void> _persistirMapa(Map<String, CaixaSessao> mapa) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = mapa.map((k, v) => MapEntry(k, v.toMap()));
    await prefs.setString(_kSessoesRede, jsonEncode(encoded));
  }

  Future<void> _migrarLegadoSeNecessario() async {
    final prefs = await SharedPreferences.getInstance();
    final legado = prefs.getString(_kLegadoSessao);
    if (legado == null || legado.trim().isEmpty) return;
    final jaTem = prefs.getString(_kSessoesRede);
    if (jaTem != null && jaTem.trim().isNotEmpty) {
      await prefs.remove(_kLegadoSessao);
      return;
    }
    try {
      final map = jsonDecode(legado) as Map<String, dynamic>;
      final terminalId = await _obterTerminalIdInterno();
      final sessao = CaixaSessao(
        terminalId: terminalId,
        aberto: map['aberto'] == true,
        operador: (map['operador'] as String?) ?? '',
        aberturaEm: DateTime.tryParse((map['aberturaEm'] ?? '').toString()),
        fundoTroco: ((map['fundoTroco'] as num?) ?? 0).toDouble(),
        suprimentos: ((map['suprimentos'] as num?) ?? 0).toDouble(),
        sangrias: ((map['sangrias'] as num?) ?? 0).toDouble(),
        atualizadoEm: DateTime.now(),
      );
      await prefs.remove(_kLegadoSessao);
      await _persistirMapa({terminalId: sessao});
    } catch (_) {
      await prefs.remove(_kLegadoSessao);
    }
  }
}

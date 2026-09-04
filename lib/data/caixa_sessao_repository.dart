import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/caixa_sessao.dart';
import '../services/lan_api_server.dart';
import 'sync/caixa_status_hub.dart';
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
    // Platform.localHostname pode travar/demorar muito no Android — evita no mobile.
    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        host = Platform.localHostname.trim();
      } catch (_) {
        host = '';
      }
    }
    id = host.isNotEmpty
        ? 'pc_$host'
        : '${Platform.isAndroid || Platform.isIOS ? 'cel' : 'terminal'}'
            '_${DateTime.now().millisecondsSinceEpoch}';
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
    // Nao usar prefs.reload() aqui: em Windows pode reler disco atrasado e
    // apagar escrita recente (KPI "Fechado" com caixa aberto na UI).
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

  Future<CaixaSessao?> obterSessaoAbertaEmOutroTerminal() async {
    final meu = await obterTerminalId();
    final todas = await listarTodasSessoes();
    for (final e in todas.entries) {
      if (e.key != meu && e.value.aberto) {
        return e.value;
      }
    }
    return null;
  }

  /// Sessao aberta deste terminal, ou a da loja quando [umCaixaAbertoPorLoja].
  static CaixaSessao? sessaoAbertaPara(
    Map<String, CaixaSessao> mapa, {
    required String terminalId,
    required bool umCaixaAbertoPorLoja,
  }) {
    final id = terminalId.trim();
    final minha = id.isEmpty ? null : mapa[id];
    if (minha != null && minha.aberto) return minha;
    if (umCaixaAbertoPorLoja) {
      for (final s in mapa.values) {
        if (s.aberto) return s;
      }
    }
    return null;
  }

  /// Soma atomica de suprimento/sangria na sessao aberta (mutex interno).
  Future<CaixaSessao> registrarMovimentacao({
    required String terminalId,
    double deltaSuprimento = 0,
    double deltaSangria = 0,
    bool umCaixaAbertoPorLoja = true,
    bool propagarRede = true,
  }) async {
    if (deltaSuprimento == 0 && deltaSangria == 0) {
      throw ArgumentError('Informe um valor de suprimento ou sangria.');
    }
    if (deltaSuprimento < 0 || deltaSangria < 0) {
      throw ArgumentError('Valor da movimentacao deve ser positivo.');
    }
    return _serializar(() async {
      final todas = await _listarTodasSessoesInterno(migrarLegado: false);
      final atual = sessaoAbertaPara(
        todas,
        terminalId: terminalId,
        umCaixaAbertoPorLoja: umCaixaAbertoPorLoja,
      );
      if (atual == null || !atual.aberto) {
        throw StateError('caixa nao aberto neste terminal');
      }
      final nova = atual.copyWith(
        suprimentos: atual.suprimentos + deltaSuprimento,
        sangrias: atual.sangrias + deltaSangria,
        atualizadoEm: DateTime.now(),
      );
      todas[atual.terminalId] = nova;
      await _persistirMapa(todas);
      CaixaStatusHub.instance.publicarDasSessoes(todas);
      if (propagarRede) {
        _propagarCaixaRede();
      }
      return nova;
    });
  }

  /// Abre sessao no mesmo mutex (evita race entre terminais).
  ///
  /// Retorna mapa com chaves: `ok`, `jaAberto`, `sessao`, `terminais`.
  /// Em conflito um-caixa: lanca [StateError] com prefixo `caixa_ja_aberto:`.
  Future<Map<String, dynamic>> abrirSessaoAtomica({
    required String terminalId,
    required String operador,
    required double fundoTroco,
    required bool umCaixaAbertoPorLoja,
    bool propagarRede = true,
  }) async {
    final id = terminalId.trim();
    final op = operador.trim();
    if (id.isEmpty || op.isEmpty) {
      throw ArgumentError('terminalId e operador obrigatorios');
    }
    final fundo = fundoTroco < 0 ? 0.0 : fundoTroco;
    return _serializar(() async {
      final mapa = await _listarTodasSessoesInterno(migrarLegado: false);
      final local = mapa[id];
      if (local?.aberto == true) {
        return {
          'ok': true,
          'jaAberto': true,
          'sessao': local!,
          'terminais': Map<String, CaixaSessao>.from(mapa),
        };
      }
      if (umCaixaAbertoPorLoja) {
        for (final e in mapa.entries) {
          if (e.key != id && e.value.aberto) {
            throw StateError(
              'caixa_ja_aberto:${e.value.terminalId}|${e.value.operador}',
            );
          }
        }
      }
      final sessao = CaixaSessao(
        terminalId: id,
        aberto: true,
        operador: op,
        aberturaEm: DateTime.now(),
        fundoTroco: fundo,
        suprimentos: 0,
        sangrias: 0,
        atualizadoEm: DateTime.now(),
      );
      mapa[id] = sessao;
      await _persistirMapa(mapa);
      CaixaStatusHub.instance.publicarDasSessoes(mapa);
      if (propagarRede) {
        _propagarCaixaRede();
      }
      return {
        'ok': true,
        'jaAberto': false,
        'sessao': sessao,
        'terminais': Map<String, CaixaSessao>.from(mapa),
      };
    });
  }

  /// Fecha sessao no mesmo mutex (evita race entre terminais).
  ///
  /// Em conflito de outro terminal sem forcar: lanca [StateError]
  /// `caixa_outro_terminal:...`.
  Future<Map<String, dynamic>> fecharSessaoAtomica({
    required String terminalId,
    required bool forcar,
    required bool umCaixaAbertoPorLoja,
    bool propagarRede = true,
  }) async {
    final id = terminalId.trim();
    if (id.isEmpty) {
      throw ArgumentError('terminalId obrigatorio');
    }
    return _serializar(() async {
      final mapa = await _listarTodasSessoesInterno(migrarLegado: false);

      CaixaSessao? alvo;
      if (mapa[id]?.aberto == true) {
        alvo = mapa[id];
      } else if (forcar || umCaixaAbertoPorLoja) {
        for (final s in mapa.values) {
          if (s.aberto) {
            alvo = s;
            break;
          }
        }
      }

      if (alvo == null || !alvo.aberto) {
        return {
          'ok': true,
          'jaFechado': true,
          'sessao': null,
          'terminais': Map<String, CaixaSessao>.from(mapa),
          'fechadasCount': mapa.values.where((s) => !s.aberto).length,
        };
      }

      if (!forcar && !umCaixaAbertoPorLoja && alvo.terminalId != id) {
        throw StateError(
          'caixa_outro_terminal:${alvo.terminalId}|${alvo.operador}',
        );
      }

      CaixaSessao fechar(CaixaSessao s) => s.copyWith(
            aberto: false,
            operador: '',
            limparAbertura: true,
            fundoTroco: 0,
            suprimentos: 0,
            sangrias: 0,
            atualizadoEm: DateTime.now(),
          );

      final fechada = fechar(alvo);
      mapa[fechada.terminalId] = fechada;

      if (forcar) {
        for (final e in mapa.entries.toList()) {
          if (e.value.aberto && e.key != fechada.terminalId) {
            mapa[e.key] = fechar(e.value);
          }
        }
      }

      await _persistirMapa(mapa);
      CaixaStatusHub.instance.publicarDasSessoes(mapa);
      if (propagarRede) {
        _propagarCaixaRede();
      }
      return {
        'ok': true,
        'jaFechado': false,
        'sessao': fechada,
        'terminais': Map<String, CaixaSessao>.from(mapa),
        'fechadasCount': mapa.values.where((s) => !s.aberto).length,
      };
    });
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
      CaixaStatusHub.instance.publicarDasSessoes(todas);
      if (propagarRede) {
        _propagarCaixaRede();
      }
    });
  }

  /// Fecha todas as sessoes abertas (fechamento aderido / um-caixa no PC servidor).
  Future<int> fecharTodasSessoesAbertas({bool propagarRede = true}) async {
    return _serializar(() async {
      final todas = await _listarTodasSessoesInterno(migrarLegado: false);
      var fechadas = 0;
      final agora = DateTime.now();
      for (final e in todas.entries) {
        if (!e.value.aberto) continue;
        todas[e.key] = e.value.copyWith(
          aberto: false,
          operador: '',
          limparAbertura: true,
          fundoTroco: 0,
          suprimentos: 0,
          sangrias: 0,
          atualizadoEm: agora,
        );
        fechadas++;
      }
      if (fechadas > 0) {
        await _persistirMapa(todas);
        CaixaStatusHub.instance.publicar(
          aberto: false,
          operador: '',
          terminalId: '',
        );
        if (propagarRede) {
          _propagarCaixaRede();
        }
      } else {
        CaixaStatusHub.instance.publicar(aberto: false);
      }
      return fechadas;
    });
  }

  void _propagarCaixaRede() {
    notificarAlteracaoParaRede(
      entidade: 'caixa_sessoes',
      entidadeId: 1,
    );
    try {
      LanApiServerHub.instance.notificar('caixa_sessoes');
      LanApiServerHub.instance.notificar('caixa');
    } catch (_) {}
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
      CaixaStatusHub.instance.publicarDasSessoes(locais);
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
        aberto: CaixaSessao.boolFrom(map['aberto']),
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

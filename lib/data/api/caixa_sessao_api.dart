import '../../model/caixa_sessao.dart';
import 'lan_api_client.dart';

/// Snapshot das sessoes de caixa no PC servidor (terminal leve).
class CaixaSessoesSnapshot {
  const CaixaSessoesSnapshot({
    required this.umCaixaAbertoPorLoja,
    required this.terminais,
    required this.abertosCount,
    this.aberta,
    this.operacaoLiberada = false,
    this.aderido = false,
    this.motivo = '',
  });

  final bool umCaixaAbertoPorLoja;
  final CaixaSessao? aberta;
  final Map<String, CaixaSessao> terminais;
  final int abertosCount;

  /// True quando este terminal pode importar orcamentos / finalizar vendas.
  final bool operacaoLiberada;
  final bool aderido;
  final String motivo;

  static CaixaSessoesSnapshot fromMap(Map<String, dynamic> m) {
    final terminais = <String, CaixaSessao>{};
    final raw = m['terminais'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.value is Map) {
          final s = CaixaSessao.fromMap(Map<String, dynamic>.from(e.value as Map));
          final id = s.terminalId.isNotEmpty ? s.terminalId : e.key.toString();
          terminais[id] = s.copyWith(terminalId: id);
        }
      }
    }
    CaixaSessao? aberta;
    final a = m['aberta'] ?? m['sessao'];
    if (a is Map) {
      aberta = CaixaSessao.fromMap(Map<String, dynamic>.from(a));
    } else {
      for (final s in terminais.values) {
        if (s.aberto) {
          aberta = s;
          break;
        }
      }
    }
    final umCaixa = m['umCaixaAbertoPorLoja'] != false;
    return CaixaSessoesSnapshot(
      umCaixaAbertoPorLoja: umCaixa,
      aberta: aberta,
      terminais: terminais,
      abertosCount: (m['abertosCount'] as num?)?.toInt() ??
          terminais.values.where((s) => s.aberto).length,
      operacaoLiberada: m['operacaoLiberada'] == true,
      aderido: m['aderido'] == true,
      motivo: (m['motivo'] ?? '').toString(),
    );
  }
}

/// Resultado de abrir/fechar caixa via API (inclui conflito 409).
class CaixaSessaoApiResultado {
  const CaixaSessaoApiResultado({
    required this.ok,
    this.sessao,
    this.terminais = const {},
    this.errorCode,
    this.message,
    this.sessaoAbertaConflito,
  });

  final bool ok;
  final CaixaSessao? sessao;
  final Map<String, CaixaSessao> terminais;
  final String? errorCode;
  final String? message;
  final CaixaSessao? sessaoAbertaConflito;

  static Map<String, CaixaSessao> _terminaisDe(Map<String, dynamic> m) {
    final out = <String, CaixaSessao>{};
    final raw = m['terminais'];
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      if (e.value is Map) {
        final s = CaixaSessao.fromMap(Map<String, dynamic>.from(e.value as Map));
        final id = s.terminalId.isNotEmpty ? s.terminalId : e.key.toString();
        out[id] = s.copyWith(terminalId: id);
      }
    }
    return out;
  }

  static CaixaSessaoApiResultado fromMap(Map<String, dynamic> m) {
    final err = (m['error'] ?? '').toString();
    final ok = m['ok'] == true && err.isEmpty;
    CaixaSessao? sessao;
    final s = m['sessao'];
    if (s is Map) {
      sessao = CaixaSessao.fromMap(Map<String, dynamic>.from(s));
    }
    CaixaSessao? conflito;
    final c = m['sessaoAberta'];
    if (c is Map) {
      conflito = CaixaSessao.fromMap(Map<String, dynamic>.from(c));
    }
    return CaixaSessaoApiResultado(
      ok: ok,
      sessao: sessao,
      terminais: _terminaisDe(m),
      errorCode: err.isEmpty ? null : err,
      message: (m['message'] ?? '').toString().trim().isEmpty
          ? null
          : (m['message'] as String?)?.toString(),
      sessaoAbertaConflito: conflito,
    );
  }
}

/// Ponte HTTP para sessoes de caixa no terminal leve.
class CaixaSessaoApi {
  CaixaSessaoApi(this._client);

  final LanApiClient _client;

  Future<CaixaSessoesSnapshot> listar() async {
    final m = await _client.listarCaixaSessoes();
    return CaixaSessoesSnapshot.fromMap(m);
  }

  Future<CaixaSessoesSnapshot> sessaoAtiva({required String terminalId}) async {
    final m = await _client.sessaoAtivaCaixa(terminalId: terminalId);
    return CaixaSessoesSnapshot.fromMap(m);
  }

  Future<CaixaSessaoApiResultado> abrir({
    required String terminalId,
    required String operador,
    double fundoTroco = 0,
  }) async {
    final m = await _client.abrirCaixaSessao(
      terminalId: terminalId,
      operador: operador,
      fundoTroco: fundoTroco,
    );
    return CaixaSessaoApiResultado.fromMap(m);
  }

  Future<CaixaSessaoApiResultado> fechar({
    required String terminalId,
    bool forcar = false,
  }) async {
    final m = await _client.fecharCaixaSessao(
      terminalId: terminalId,
      forcar: forcar,
    );
    return CaixaSessaoApiResultado.fromMap(m);
  }

  /// Desbloqueia sessoes orfas no servidor (fecha todas).
  Future<CaixaSessaoApiResultado> reset({String motivo = 'reset_admin'}) async {
    final m = await _client.resetCaixaSessoes(motivo: motivo);
    return CaixaSessaoApiResultado.fromMap(m);
  }

  Future<CaixaSessaoApiResultado> atualizar({
    required String terminalId,
    String? operador,
    double? fundoTroco,
    double? suprimentos,
    double? sangrias,
  }) async {
    final m = await _client.atualizarCaixaSessao(
      terminalId: terminalId,
      operador: operador,
      fundoTroco: fundoTroco,
      suprimentos: suprimentos,
      sangrias: sangrias,
    );
    return CaixaSessaoApiResultado.fromMap(m);
  }

  /// Incremento atomico de suprimento/sangria no servidor (evita lost update).
  Future<CaixaSessaoApiResultado> registrarMovimentacao({
    required String terminalId,
    required String tipo,
    required double valor,
  }) async {
    final m = await _client.movimentacaoCaixaSessao(
      terminalId: terminalId,
      tipo: tipo,
      valor: valor,
    );
    return CaixaSessaoApiResultado.fromMap(m);
  }
}

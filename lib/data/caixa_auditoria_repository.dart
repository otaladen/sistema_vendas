import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/caixa_auditoria_evento.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

/// Registro de auditoria do caixa (prefs + ObjectBox).
class CaixaAuditoriaRegistro {
  CaixaAuditoriaRegistro({
    required this.em,
    required this.evento,
    required this.usuario,
    required this.operadorCaixa,
    required this.detalhes,
  });

  final DateTime em;
  final String evento;
  final String usuario;
  final String operadorCaixa;
  final Map<String, dynamic> detalhes;

  factory CaixaAuditoriaRegistro.fromMap(Map<String, dynamic> map) {
    final emRaw = map['em']?.toString() ?? '';
    DateTime em;
    try {
      em = DateTime.parse(emRaw);
    } catch (_) {
      em = DateTime.now();
    }
    final det = map['detalhes'];
    return CaixaAuditoriaRegistro(
      em: em,
      evento: map['evento']?.toString() ?? '',
      usuario: map['usuario']?.toString() ?? '',
      operadorCaixa: map['operadorCaixa']?.toString() ?? '',
      detalhes: det is Map
          ? det.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() => {
        'em': em.toIso8601String(),
        'evento': evento,
        'usuario': usuario,
        'operadorCaixa': operadorCaixa,
        'detalhes': detalhes,
      };

  bool get ehFechamento => evento == 'fechamento_caixa';

  bool get ehPersistente =>
      CaixaAuditoriaRepository.ehEventoPersistente(evento);

  double? get diferencaTotal {
    final v = detalhes['diferencaTotal'];
    if (v is num) return v.toDouble();
    return null;
  }

  double get valor =>
      CaixaAuditoriaRepository.valorDoEvento(evento, detalhes);
}

/// Leitura/gravação da auditoria do caixa.
///
/// Prefs (`caixa_auditoria_eventos_v1`) continuam como espelho operacional.
/// Suprimento, sangria e fechamento tambem vao para ObjectBox
/// ([CaixaAuditoriaEvento]) para consulta historica.
class CaixaAuditoriaRepository {
  CaixaAuditoriaRepository({ObjectBox? db}) : _db = db;

  static const String chavePrefs = 'caixa_auditoria_eventos_v1';

  static const Set<String> eventosPersistentes = {
    'suprimento',
    'sangria',
    'fechamento_caixa',
  };

  final ObjectBox? _db;

  static bool ehEventoPersistente(String evento) =>
      eventosPersistentes.contains(evento.trim());

  static String formatarDataLocal(DateTime em) {
    final local = em.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String formatarHoraLocal(DateTime em) {
    final local = em.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$min:$s';
  }

  static double valorDoEvento(
    String evento,
    Map<String, dynamic> detalhes,
  ) {
    final direto = detalhes['valor'];
    if (direto is num) return direto.toDouble();
    if (evento == 'fechamento_caixa') {
      final declarado = detalhes['declaradoDinheiro'];
      if (declarado is num) return declarado.toDouble();
    }
    return 0;
  }

  static Map<String, dynamic> enriquecerDetalhes({
    required String evento,
    required DateTime em,
    required String operador,
    Map<String, dynamic>? detalhes,
  }) {
    final mapa = <String, dynamic>{
      if (detalhes != null) ...detalhes,
    };
    mapa['tipo'] = evento;
    final operadorAtual = mapa['operador']?.toString().trim() ?? '';
    mapa['operador'] = operadorAtual.isNotEmpty ? operadorAtual : operador;
    final dataAtual = mapa['data']?.toString().trim() ?? '';
    mapa['data'] =
        dataAtual.isNotEmpty ? dataAtual : formatarDataLocal(em);
    final horaAtual = mapa['hora']?.toString().trim() ?? '';
    mapa['hora'] =
        horaAtual.isNotEmpty ? horaAtual : formatarHoraLocal(em);
    mapa['valor'] = valorDoEvento(evento, mapa);
    return mapa;
  }

  /// Grava (ou atualiza) o evento persistente no ObjectBox.
  void gravarObjectBox({
    required DateTime em,
    required String evento,
    required String usuario,
    required String operadorCaixa,
    Map<String, dynamic>? detalhes,
  }) {
    final db = _db;
    if (db == null || !ehEventoPersistente(evento)) return;
    final det = enriquecerDetalhes(
      evento: evento,
      em: em,
      operador: operadorCaixa,
      detalhes: detalhes,
    );
    final operador = (det['operador']?.toString() ?? operadorCaixa).trim();
    db.caixaAuditoriaEventoBox.put(
      CaixaAuditoriaEvento(
        dataHora: em,
        data: det['data']?.toString() ?? formatarDataLocal(em),
        hora: det['hora']?.toString() ?? formatarHoraLocal(em),
        tipo: evento.trim(),
        operador: operador,
        usuario: usuario.trim(),
        valor: valorDoEvento(evento, det),
        detalhesJson: jsonEncode(det),
      ),
    );
  }

  Future<List<CaixaAuditoriaRegistro>> listarTodos() async {
    final prefs = await _lerPrefs();
    _importarPrefsPendentes(prefs);
    final ob = _lerObjectBox();
    return _mesclar(objectBox: ob, prefs: prefs)
      ..sort((a, b) => b.em.compareTo(a.em));
  }

  Future<List<CaixaAuditoriaRegistro>> listarFechamentos() async {
    return (await listarTodos()).where((r) => r.ehFechamento).toList();
  }

  Future<List<Map<String, dynamic>>> listarTodosComoMapas() async {
    return (await listarTodos()).map((e) => e.toMap()).toList();
  }

  Future<void> substituirTodos(List<Map<String, dynamic>> registros) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chavePrefs, jsonEncode(registros));
    final db = _db;
    if (db == null) return;
    db.caixaAuditoriaEventoBox.removeAll();
    for (final raw in registros) {
      final r = CaixaAuditoriaRegistro.fromMap(raw);
      gravarObjectBox(
        em: r.em,
        evento: r.evento,
        usuario: r.usuario,
        operadorCaixa: r.operadorCaixa,
        detalhes: r.detalhes,
      );
    }
  }

  List<CaixaAuditoriaRegistro> _lerObjectBox() {
    final db = _db;
    if (db == null) return const [];
    try {
      final q = db.caixaAuditoriaEventoBox
          .query()
          .order(CaixaAuditoriaEvento_.dataHora, flags: Order.descending)
          .build();
      try {
        return q.find().map(_deEntidade).toList();
      } finally {
        q.close();
      }
    } catch (_) {
      return const [];
    }
  }

  Future<List<CaixaAuditoriaRegistro>> _lerPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(chavePrefs);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => CaixaAuditoriaRegistro.fromMap(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _importarPrefsPendentes(List<CaixaAuditoriaRegistro> prefs) {
    final db = _db;
    if (db == null) return;
    final existentes = {
      for (final e in _lerObjectBox()) _chave(e),
    };
    for (final r in prefs) {
      if (!r.ehPersistente) continue;
      if (existentes.contains(_chave(r))) continue;
      gravarObjectBox(
        em: r.em,
        evento: r.evento,
        usuario: r.usuario,
        operadorCaixa: r.operadorCaixa,
        detalhes: r.detalhes,
      );
      existentes.add(_chave(r));
    }
  }

  List<CaixaAuditoriaRegistro> _mesclar({
    required List<CaixaAuditoriaRegistro> objectBox,
    required List<CaixaAuditoriaRegistro> prefs,
  }) {
    final saida = <CaixaAuditoriaRegistro>[];
    final vistos = <String>{};
    for (final r in objectBox) {
      final k = _chave(r);
      if (vistos.add(k)) saida.add(r);
    }
    for (final r in prefs) {
      final k = _chave(r);
      if (vistos.add(k)) saida.add(r);
    }
    return saida;
  }

  static String _chave(CaixaAuditoriaRegistro r) {
    final data = r.detalhes['data']?.toString().trim().isNotEmpty == true
        ? r.detalhes['data'].toString()
        : formatarDataLocal(r.em);
    final hora = r.detalhes['hora']?.toString().trim().isNotEmpty == true
        ? r.detalhes['hora'].toString()
        : formatarHoraLocal(r.em);
    final valor = r.valor.toStringAsFixed(2);
    return '$data|$hora|${r.evento}|$valor|${r.operadorCaixa}|${r.usuario}';
  }

  static CaixaAuditoriaRegistro _deEntidade(CaixaAuditoriaEvento e) {
    Map<String, dynamic> detalhes = {};
    if (e.detalhesJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(e.detalhesJson);
        if (decoded is Map) {
          detalhes = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }
    detalhes['tipo'] = e.tipo;
    detalhes['operador'] = e.operador;
    detalhes['valor'] = e.valor;
    detalhes['data'] = e.data;
    detalhes['hora'] = e.hora;
    return CaixaAuditoriaRegistro(
      em: e.dataHora,
      evento: e.tipo,
      usuario: e.usuario,
      operadorCaixa: e.operador,
      detalhes: detalhes,
    );
  }
}

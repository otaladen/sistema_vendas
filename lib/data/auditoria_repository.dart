import 'dart:convert';

import '../domain/auditoria_catalogo.dart';
import '../model/auditoria_evento.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class AuditoriaFiltro {
  const AuditoriaFiltro({
    this.inicio,
    this.fim,
    this.modulo,
    this.usuarioLogin,
    this.termoBusca,
    this.limite = 3000,
  });

  final DateTime? inicio;
  final DateTime? fim;
  final String? modulo;
  final String? usuarioLogin;
  final String? termoBusca;
  final int limite;
}

class AuditoriaRepository {
  AuditoriaRepository(this._db);

  final ObjectBox _db;

  void registrar({
    required String modulo,
    required String acao,
    String usuarioLogin = '',
    String entidade = '',
    String entidadeId = '',
    String resumo = '',
    Map<String, dynamic>? detalhes,
    DateTime? dataHora,
  }) {
    final evento = AuditoriaEvento(
      dataHora: dataHora ?? DateTime.now(),
      usuarioLogin: usuarioLogin.trim(),
      modulo: modulo.trim(),
      acao: acao.trim(),
      entidade: entidade.trim(),
      entidadeId: entidadeId.trim(),
      resumo: resumo.trim(),
      detalhesJson: detalhes == null || detalhes.isEmpty
          ? ''
          : jsonEncode(detalhes),
    );
    final id = _db.auditoriaEventoBox.put(evento);
    notificarAlteracaoParaRede(entidade: 'auditoria_evento', entidadeId: id);
  }

  List<AuditoriaEvento> listar({AuditoriaFiltro filtro = const AuditoriaFiltro()}) {
    final q = _db.auditoriaEventoBox
        .query()
        .order(AuditoriaEvento_.dataHora, flags: Order.descending)
        .build();
    try {
      var lista = q.find();
      final inicio = filtro.inicio;
      final fim = filtro.fim;
      if (inicio != null) {
        final iniUtc = inicio.toUtc();
        lista = lista
            .where((e) => !e.dataHora.toUtc().isBefore(iniUtc))
            .toList();
      }
      if (fim != null) {
        final fimUtc = DateTime(
          fim.year,
          fim.month,
          fim.day,
          23,
          59,
          59,
          999,
        ).toUtc();
        lista = lista
            .where((e) => !e.dataHora.toUtc().isAfter(fimUtc))
            .toList();
      }
      final modulo = filtro.modulo?.trim();
      if (modulo != null && modulo.isNotEmpty) {
        lista = lista.where((e) => e.modulo == modulo).toList();
      }
      final usuario = filtro.usuarioLogin?.trim().toLowerCase();
      if (usuario != null && usuario.isNotEmpty) {
        lista = lista
            .where((e) => e.usuarioLogin.toLowerCase().contains(usuario))
            .toList();
      }
      final termo = filtro.termoBusca?.trim().toLowerCase();
      if (termo != null && termo.isNotEmpty) {
        lista = lista.where((e) {
          final blob = [
            e.resumo,
            e.entidade,
            e.entidadeId,
            e.usuarioLogin,
            e.modulo,
            e.acao,
            e.detalhesJson,
            auditoriaRotuloModulo(e.modulo),
            auditoriaRotuloAcao(e.acao),
          ].join(' ').toLowerCase();
          return blob.contains(termo);
        }).toList();
      }
      if (lista.length > filtro.limite) {
        lista = lista.take(filtro.limite).toList();
      }
      return lista;
    } finally {
      q.close();
    }
  }

  List<String> listarUsuariosDistintos({int limite = 200}) {
    final q = _db.auditoriaEventoBox.query().build();
    try {
      final logins = <String>{};
      for (final e in q.find()) {
        final l = e.usuarioLogin.trim();
        if (l.isNotEmpty) logins.add(l);
        if (logins.length >= limite) break;
      }
      final lista = logins.toList()..sort();
      return lista;
    } finally {
      q.close();
    }
  }

  /// Eventos com [dataHora] ate o fim do dia [ate] (inclusive).
  int contarAteFimDoDia(DateTime ate) {
    final corteMs = _fimDoDiaUtc(ate).millisecondsSinceEpoch;
    final q = _db.auditoriaEventoBox
        .query(AuditoriaEvento_.dataHora.lessOrEqual(corteMs))
        .build();
    try {
      return q.count();
    } finally {
      q.close();
    }
  }

  /// Remove eventos com [dataHora] ate o fim do dia [ate] (inclusive).
  int excluirAteFimDoDia(DateTime ate) {
    final corteMs = _fimDoDiaUtc(ate).millisecondsSinceEpoch;
    return _db.store.runInTransaction(TxMode.write, () {
      final q = _db.auditoriaEventoBox
          .query(AuditoriaEvento_.dataHora.lessOrEqual(corteMs))
          .build();
      try {
        final ids = q.findIds();
        if (ids.isEmpty) return 0;
        _db.auditoriaEventoBox.removeMany(ids);
        return ids.length;
      } finally {
        q.close();
      }
    });
  }

  /// Remove eventos anteriores ao inicio do dia de corte (politica de retencao).
  int purgarAnterioresARetencaoDias(int diasRetencao) {
    if (diasRetencao <= 0) return 0;
    final hoje = DateTime.now();
    final limiteLocal = DateTime(hoje.year, hoje.month, hoje.day)
        .subtract(Duration(days: diasRetencao));
    final corteMs = limiteLocal.toUtc().millisecondsSinceEpoch;
    return _db.store.runInTransaction(TxMode.write, () {
      final q = _db.auditoriaEventoBox
          .query(AuditoriaEvento_.dataHora.lessThan(corteMs))
          .build();
      try {
        final ids = q.findIds();
        if (ids.isEmpty) return 0;
        _db.auditoriaEventoBox.removeMany(ids);
        return ids.length;
      } finally {
        q.close();
      }
    });
  }

  int contarTotal() => _db.auditoriaEventoBox.count();

  static DateTime _fimDoDiaUtc(DateTime dia) {
    return DateTime(
      dia.year,
      dia.month,
      dia.day,
      23,
      59,
      59,
      999,
    ).toUtc();
  }

  Map<String, dynamic>? detalhesMap(AuditoriaEvento evento) {
    final raw = evento.detalhesJson.trim();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }
}

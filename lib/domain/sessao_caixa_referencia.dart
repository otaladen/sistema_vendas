import '../data/caixa_auditoria_repository.dart';
import '../model/caixa_sessao.dart';

/// Identificador de um turno de caixa (abertura ate fechamento ou sessao aberta).
class SessaoCaixaReferencia {
  const SessaoCaixaReferencia({
    required this.numero,
    required this.chave,
    required this.aberturaEm,
    this.fechamentoEm,
    required this.operador,
    this.terminalId = '',
    this.fundoTroco = 0,
    this.suprimentos = 0,
    this.sangrias = 0,
    this.aberta = false,
  });

  /// Numero sequencial exibido ao usuario (1 = mais antigo no catalogo).
  final int numero;

  /// Chave estavel para dropdown / filtros.
  final String chave;
  final DateTime aberturaEm;
  final DateTime? fechamentoEm;
  final String operador;
  final String terminalId;
  final double fundoTroco;
  final double suprimentos;
  final double sangrias;
  final bool aberta;

  /// Inicio/fim UTC para filtrar vendas finalizadas no caixa (turno fechado).
  (DateTime inicioUtc, DateTime fimUtc) intervaloFiltroVendasUtc({
    DateTime? agora,
  }) {
    final fimBase = fechamentoEm ?? agora ?? DateTime.now();
    var fim = fimBase.toUtc().add(const Duration(minutes: 1));
    var inicio = aberturaEm.toUtc();
    if (fim.isBefore(inicio)) {
      inicio = fim.subtract(const Duration(hours: 8));
    }
    return (inicio, fim);
  }

  /// Abertura do turno quando falta [aberturaEm] no fechamento.
  ///
  /// Varios caixas no mesmo dia: inicio = logo apos o fechamento anterior,
  /// nao meia-noite (evita misturar turno da manha com o da tarde).
  static DateTime inferirAberturaComContexto({
    required CaixaAuditoriaRegistro fechamento,
    DateTime? aberturaPareada,
    required List<CaixaAuditoriaRegistro> fechamentosMesmoContexto,
  }) {
    if (aberturaPareada != null) {
      final mins = fechamento.em.difference(aberturaPareada).inMinutes;
      if (mins >= 2) return aberturaPareada;
    }
    final loc = fechamento.em.toLocal();
    DateTime? ultimoFechamentoAntes;
    for (final f in fechamentosMesmoContexto) {
      if (!f.ehFechamento) continue;
      if (!f.em.isBefore(fechamento.em)) continue;
      if ((f.em.toUtc().millisecondsSinceEpoch -
              fechamento.em.toUtc().millisecondsSinceEpoch)
          .abs() <
          1000) {
        continue;
      }
      final fl = f.em.toLocal();
      if (fl.year != loc.year ||
          fl.month != loc.month ||
          fl.day != loc.day) {
        continue;
      }
      if (ultimoFechamentoAntes == null ||
          f.em.isAfter(ultimoFechamentoAntes)) {
        ultimoFechamentoAntes = f.em;
      }
    }
    if (ultimoFechamentoAntes != null) {
      return ultimoFechamentoAntes.add(const Duration(seconds: 1));
    }
    return DateTime(loc.year, loc.month, loc.day);
  }

  SessaoCaixaReferencia copyWith({DateTime? aberturaEm}) {
    if (aberturaEm == null || aberturaEm == this.aberturaEm) return this;
    return SessaoCaixaReferencia(
      numero: numero,
      chave: gerarChave(
        abertura: aberturaEm,
        fechamento: fechamentoEm,
        operador: operador,
        terminalId: terminalId,
      ),
      aberturaEm: aberturaEm,
      fechamentoEm: fechamentoEm,
      operador: operador,
      terminalId: terminalId,
      fundoTroco: fundoTroco,
      suprimentos: suprimentos,
      sangrias: sangrias,
      aberta: aberta,
    );
  }

  static String gerarChave({
    required DateTime abertura,
    DateTime? fechamento,
    required String operador,
    String terminalId = '',
  }) {
    final ab = abertura.toUtc().millisecondsSinceEpoch;
    final fc = fechamento?.toUtc().millisecondsSinceEpoch ?? 0;
    final op = operador.trim();
    final term = terminalId.trim();
    return '$ab|$fc|$op|$term';
  }

  /// Monta sessao fechada com abertura coerente (pareamento + turnos no mesmo dia).
  static SessaoCaixaReferencia montarSessaoFechamento({
    required CaixaAuditoriaRegistro fechamento,
    required int numero,
    DateTime? aberturaPareada,
    List<CaixaAuditoriaRegistro> fechamentosContexto = const [],
  }) {
    final base = SessaoCaixaReferencia.deFechamento(
      fechamento,
      numero: numero,
      aberturaEm: aberturaPareada,
    );
    final ab = inferirAberturaComContexto(
      fechamento: fechamento,
      aberturaPareada: aberturaPareada ?? base.aberturaEm,
      fechamentosMesmoContexto: fechamentosContexto,
    );
    return base.copyWith(aberturaEm: ab);
  }

  factory SessaoCaixaReferencia.deFechamento(
    CaixaAuditoriaRegistro fechamento, {
    required int numero,
    DateTime? aberturaEm,
  }) {
    final d = fechamento.detalhes;
    final operador =
        (d['operador']?.toString() ?? fechamento.operadorCaixa).trim();
    final terminal = (d['sessaoFechada'] ?? '').toString();
    final abRaw = d['aberturaEm']?.toString().trim();
    final parsedAb =
        abRaw != null && abRaw.isNotEmpty ? DateTime.tryParse(abRaw) : null;
    final aberturaInicial = aberturaEm ?? parsedAb;
    return SessaoCaixaReferencia(
      numero: numero,
      chave: gerarChave(
        abertura: aberturaInicial ?? fechamento.em,
        fechamento: fechamento.em,
        operador: operador,
        terminalId: terminal,
      ),
      aberturaEm: aberturaInicial ?? fechamento.em,
      fechamentoEm: fechamento.em,
      operador: operador,
      terminalId: terminal,
      fundoTroco: _num(d['fundoTroco']),
      suprimentos: _num(d['suprimentos']),
      sangrias: _num(d['sangrias']),
      aberta: false,
    );
  }

  factory SessaoCaixaReferencia.deSessaoAberta(
    CaixaSessao sessao, {
    required int numero,
  }) {
    final abertura = sessao.aberturaEm ?? DateTime.now();
    final operador = sessao.operador.trim();
    return SessaoCaixaReferencia(
      numero: numero,
      chave: gerarChave(
        abertura: abertura,
        operador: operador,
        terminalId: sessao.terminalId,
      ),
      aberturaEm: abertura,
      fechamentoEm: null,
      operador: operador,
      terminalId: sessao.terminalId,
      fundoTroco: sessao.fundoTroco,
      suprimentos: sessao.suprimentos,
      sangrias: sessao.sangrias,
      aberta: true,
    );
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return 0;
  }
}

/// Monta a lista de sessoes a partir da auditoria de caixa (+ sessoes abertas).
abstract final class SessaoCaixaCatalogo {
  SessaoCaixaCatalogo._();

  static List<SessaoCaixaReferencia> montarDeAuditoria(
    List<CaixaAuditoriaRegistro> eventos, {
    Iterable<CaixaSessao> sessoesAbertas = const [],
  }) {
    final ordenados = List<CaixaAuditoriaRegistro>.from(eventos)
      ..sort((a, b) => a.em.compareTo(b.em));

    final aberturasPendentes = <_AberturaPendente>[];
    final fechadas = <SessaoCaixaReferencia>[];
    var seqFechada = 0;

    for (final r in ordenados) {
      switch (r.evento) {
        case 'abertura_caixa':
          aberturasPendentes.add(
            _AberturaPendente(
              em: r.em,
              operador:
                  (r.detalhes['operador']?.toString() ?? r.operadorCaixa).trim(),
              fundoTroco: _num(r.detalhes['fundoTroco']),
            ),
          );
          break;
        case 'fechamento_caixa':
          seqFechada++;
          final d = r.detalhes;
          final operador =
              (d['operador']?.toString() ?? r.operadorCaixa).trim();
          DateTime? abertura;
          final abRaw = d['aberturaEm']?.toString().trim();
          if (abRaw != null && abRaw.isNotEmpty) {
            abertura = DateTime.tryParse(abRaw);
          }
          if (abertura == null && aberturasPendentes.isNotEmpty) {
            var idx = aberturasPendentes.lastIndexWhere(
              (a) => a.operador == operador && operador.isNotEmpty,
            );
            if (idx < 0) idx = aberturasPendentes.length - 1;
            abertura = aberturasPendentes.removeAt(idx).em;
          }
          fechadas.add(
            SessaoCaixaReferencia.deFechamento(
              r,
              numero: seqFechada,
              aberturaEm: abertura,
            ),
          );
          break;
      }
    }

    final abertas = <SessaoCaixaReferencia>[];
    var seqAberta = fechadas.length;
    for (final s in sessoesAbertas) {
      if (!s.aberto || s.aberturaEm == null) continue;
      seqAberta++;
      abertas.add(SessaoCaixaReferencia.deSessaoAberta(s, numero: seqAberta));
    }

    final saida = [...fechadas, ...abertas];
    saida.sort((a, b) => b.aberturaEm.compareTo(a.aberturaEm));
    return saida;
  }

  /// Apenas registros de fechamento (ja ordenados do mais recente).
  static List<SessaoCaixaReferencia> montarDeFechamentos(
    List<CaixaAuditoriaRegistro> fechamentos, {
    Iterable<CaixaSessao> sessoesAbertas = const [],
  }) {
    final fechadas = <SessaoCaixaReferencia>[];
    final vistos = <String>{};
    var idx = 0;
    for (final r in fechamentos) {
      if (!r.ehFechamento) continue;
      idx++;
      final ref = SessaoCaixaReferencia.deFechamento(
        r,
        numero: fechamentos.length - idx + 1,
      );
      if (!vistos.add(ref.chave)) continue;
      fechadas.add(ref);
    }
    final abertas = <SessaoCaixaReferencia>[];
    for (final s in sessoesAbertas) {
      if (!s.aberto || s.aberturaEm == null) continue;
      abertas.add(
        SessaoCaixaReferencia.deSessaoAberta(s, numero: 0),
      );
    }
    final saida = [...abertas, ...fechadas];
    saida.sort((a, b) => b.aberturaEm.compareTo(a.aberturaEm));
    return saida;
  }

  static List<SessaoCaixaReferencia> filtrarBusca(
    List<SessaoCaixaReferencia> lista,
    String busca,
  ) {
    final q = busca.trim().toLowerCase();
    if (q.isEmpty) return lista;
    return lista.where((s) {
      final op = s.operador.toLowerCase();
      final term = s.terminalId.toLowerCase();
      final num = '${s.numero}';
      final ab = s.aberturaEm.toLocal();
      final data =
          '${ab.day.toString().padLeft(2, '0')}/${ab.month.toString().padLeft(2, '0')}/${ab.year}';
      final hora =
          '${ab.hour.toString().padLeft(2, '0')}:${ab.minute.toString().padLeft(2, '0')}';
      final hay = '$op $term $num $data $hora sessao';
      return hay.contains(q);
    }).toList();
  }

  static SessaoCaixaReferencia? porChave(
    String? chave,
    List<SessaoCaixaReferencia> catalogo,
  ) {
    if (chave == null || chave.trim().isEmpty) return null;
    for (final s in catalogo) {
      if (s.chave == chave) return s;
    }
    return null;
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return 0;
  }
}

class _AberturaPendente {
  _AberturaPendente({
    required this.em,
    required this.operador,
    required this.fundoTroco,
  });

  final DateTime em;
  final String operador;
  final double fundoTroco;
}

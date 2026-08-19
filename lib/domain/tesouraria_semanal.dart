import '../data/models/conta_pagar.dart';
import '../data/objectbox.dart';
import '../data/venda_repository.dart';
import '../model/recebimento_fiado.dart';

/// Totais de um dia na visao de tesouraria.
class TesourariaLinhaDia {
  const TesourariaLinhaDia({
    required this.dia,
    this.entradasPrevistas = 0,
    this.saidasPrevistas = 0,
    this.entradasRealizadas = 0,
    this.saidasRealizadas = 0,
    this.qtdEntradasPrevistas = 0,
    this.qtdSaidasPrevistas = 0,
    this.qtdEntradasRealizadas = 0,
    this.qtdSaidasRealizadas = 0,
  });

  final DateTime dia;
  final double entradasPrevistas;
  final double saidasPrevistas;
  final double entradasRealizadas;
  final double saidasRealizadas;
  final int qtdEntradasPrevistas;
  final int qtdSaidasPrevistas;
  final int qtdEntradasRealizadas;
  final int qtdSaidasRealizadas;

  double get saldoPrevisto => entradasPrevistas - saidasPrevistas;
  double get saldoRealizado => entradasRealizadas - saidasRealizadas;

  bool get ehHoje {
    final hoje = DateTime.now();
    return dia.year == hoje.year &&
        dia.month == hoje.month &&
        dia.day == hoje.day;
  }

  bool get ehPassado {
    final hoje = DateTime.now();
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    return dia.isBefore(base);
  }
}

/// Item detalhado para drill-down por dia.
class TesourariaItemDetalhe {
  const TesourariaItemDetalhe({
    required this.tipo,
    required this.descricao,
    required this.valor,
    required this.referencia,
    this.realizado = false,
  });

  final String tipo;
  final String descricao;
  final double valor;
  final String referencia;
  final bool realizado;
}

/// Resumo completo da tesouraria (7 dias passados + 7 futuros).
class TesourariaSemanalSnapshot {
  const TesourariaSemanalSnapshot({
    required this.dias,
    required this.itensPorDia,
    required this.totalEntradasPrevistas,
    required this.totalSaidasPrevistas,
    required this.totalEntradasRealizadas,
    required this.totalSaidasRealizadas,
  });

  final List<TesourariaLinhaDia> dias;
  final Map<DateTime, List<TesourariaItemDetalhe>> itensPorDia;
  final double totalEntradasPrevistas;
  final double totalSaidasPrevistas;
  final double totalEntradasRealizadas;
  final double totalSaidasRealizadas;

  double get saldoPrevistoSemana =>
      totalEntradasPrevistas - totalSaidasPrevistas;

  double get saldoRealizadoSemana =>
      totalEntradasRealizadas - totalSaidasRealizadas;

  factory TesourariaSemanalSnapshot.fromMap(Map<String, dynamic> m) {
    final diasRaw = m['dias'];
    final dias = <TesourariaLinhaDia>[];
    if (diasRaw is List) {
      for (final raw in diasRaw.whereType<Map>()) {
        final d = Map<String, dynamic>.from(raw);
        dias.add(
          TesourariaLinhaDia(
            dia: () {
              final rawDia =
                  DateTime.tryParse((d['dia'] ?? '').toString())?.toLocal() ??
                      DateTime.now();
              return DateTime(rawDia.year, rawDia.month, rawDia.day);
            }(),
            entradasPrevistas: (d['entradasPrevistas'] as num?)?.toDouble() ?? 0,
            saidasPrevistas: (d['saidasPrevistas'] as num?)?.toDouble() ?? 0,
            entradasRealizadas:
                (d['entradasRealizadas'] as num?)?.toDouble() ?? 0,
            saidasRealizadas: (d['saidasRealizadas'] as num?)?.toDouble() ?? 0,
            qtdEntradasPrevistas:
                (d['qtdEntradasPrevistas'] as num?)?.toInt() ?? 0,
            qtdSaidasPrevistas: (d['qtdSaidasPrevistas'] as num?)?.toInt() ?? 0,
            qtdEntradasRealizadas:
                (d['qtdEntradasRealizadas'] as num?)?.toInt() ?? 0,
            qtdSaidasRealizadas:
                (d['qtdSaidasRealizadas'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    final itensPorDia = <DateTime, List<TesourariaItemDetalhe>>{};
    final itensRaw = m['itensPorDia'];
    if (itensRaw is Map) {
      for (final e in itensRaw.entries) {
        final chave = e.key.toString();
        DateTime? dia;
        final parsed = DateTime.tryParse(chave);
        if (parsed != null) {
          dia = DateTime(parsed.year, parsed.month, parsed.day);
        } else {
          final parts = chave.split('-');
          if (parts.length == 3) {
            final y = int.tryParse(parts[0]);
            final mo = int.tryParse(parts[1]);
            final d = int.tryParse(parts[2]);
            if (y != null && mo != null && d != null) {
              dia = DateTime(y, mo, d);
            }
          }
        }
        if (dia == null) continue;
        final lista = <TesourariaItemDetalhe>[];
        if (e.value is List) {
          for (final raw in (e.value as List).whereType<Map>()) {
            final i = Map<String, dynamic>.from(raw);
            lista.add(
              TesourariaItemDetalhe(
                tipo: (i['tipo'] ?? '').toString(),
                descricao: (i['descricao'] ?? '').toString(),
                valor: (i['valor'] as num?)?.toDouble() ?? 0,
                referencia: (i['referencia'] ?? '').toString(),
                realizado: i['realizado'] == true,
              ),
            );
          }
        }
        itensPorDia[dia] = lista;
      }
    }
    return TesourariaSemanalSnapshot(
      dias: dias,
      itensPorDia: itensPorDia,
      totalEntradasPrevistas:
          (m['totalEntradasPrevistas'] as num?)?.toDouble() ?? 0,
      totalSaidasPrevistas: (m['totalSaidasPrevistas'] as num?)?.toDouble() ?? 0,
      totalEntradasRealizadas:
          (m['totalEntradasRealizadas'] as num?)?.toDouble() ?? 0,
      totalSaidasRealizadas:
          (m['totalSaidasRealizadas'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Agrega vencimentos e movimentos para planejamento de caixa.
class TesourariaSemanalService {
  TesourariaSemanalService._();

  static DateTime _data(DateTime d) => DateTime(d.year, d.month, d.day);

  static TesourariaSemanalSnapshot montar({
    required VendaRepository vendaRepository,
    required ObjectBox objectBox,
    int diasPassado = 7,
    int diasFuturo = 7,
  }) {
    vendaRepository.titulos.migrarTitulosLegadoSeNecessario();
    final hoje = _data(DateTime.now());
    final inicio = hoje.subtract(Duration(days: diasPassado));
    final fim = hoje.add(Duration(days: diasFuturo - 1));

    final dias = <DateTime>[];
    for (var d = inicio; !d.isAfter(fim); d = d.add(const Duration(days: 1))) {
      dias.add(d);
    }

    final mapa = {
      for (final d in dias)
        d: TesourariaLinhaDia(dia: d),
    };
    final itens = <DateTime, List<TesourariaItemDetalhe>>{
      for (final d in dias) d: [],
    };

    void addPrevisto(DateTime dia, double v, bool entrada, String tipo) {
      final key = _data(dia);
      if (!mapa.containsKey(key)) return;
      final cur = mapa[key]!;
      mapa[key] = TesourariaLinhaDia(
        dia: cur.dia,
        entradasPrevistas:
            cur.entradasPrevistas + (entrada ? v : 0),
        saidasPrevistas: cur.saidasPrevistas + (entrada ? 0 : v),
        entradasRealizadas: cur.entradasRealizadas,
        saidasRealizadas: cur.saidasRealizadas,
        qtdEntradasPrevistas:
            cur.qtdEntradasPrevistas + (entrada ? 1 : 0),
        qtdSaidasPrevistas: cur.qtdSaidasPrevistas + (entrada ? 0 : 1),
        qtdEntradasRealizadas: cur.qtdEntradasRealizadas,
        qtdSaidasRealizadas: cur.qtdSaidasRealizadas,
      );
    }

    void addRealizado(DateTime dia, double v, bool entrada, String tipo) {
      final key = _data(dia);
      if (!mapa.containsKey(key)) return;
      final cur = mapa[key]!;
      mapa[key] = TesourariaLinhaDia(
        dia: cur.dia,
        entradasPrevistas: cur.entradasPrevistas,
        saidasPrevistas: cur.saidasPrevistas,
        entradasRealizadas:
            cur.entradasRealizadas + (entrada ? v : 0),
        saidasRealizadas: cur.saidasRealizadas + (entrada ? 0 : v),
        qtdEntradasPrevistas: cur.qtdEntradasPrevistas,
        qtdSaidasPrevistas: cur.qtdSaidasPrevistas,
        qtdEntradasRealizadas:
            cur.qtdEntradasRealizadas + (entrada ? 1 : 0),
        qtdSaidasRealizadas: cur.qtdSaidasRealizadas + (entrada ? 0 : 1),
      );
    }

    for (final l in vendaRepository.titulos.listarTodosAbertos()) {
      final venc = _data(l.titulo.vencimento.toLocal());
      if (venc.isBefore(inicio) || venc.isAfter(fim)) continue;
      final v = l.titulo.saldo;
      if (v <= 0.001) continue;
      addPrevisto(venc, v, true, 'fiado');
      itens[venc]!.add(
        TesourariaItemDetalhe(
          tipo: 'A receber',
          descricao: l.nomeCliente,
          valor: v,
          referencia:
              'Venda ${l.numeroOrcamento} · parc ${l.titulo.numeroParcela}/${l.titulo.totalParcelas}',
        ),
      );
    }

    for (final c in objectBox.contaPagarBox.getAll()) {
      if (c.status == ContaPagarStatus.pago) {
        final pg = c.dataPagamento;
        if (pg == null) continue;
        final diaPg = _data(pg.toLocal());
        if (diaPg.isBefore(inicio) || diaPg.isAfter(fim)) continue;
        final v = c.valorPago ?? c.valorParcela;
        addRealizado(diaPg, v, false, 'pago');
        itens[diaPg]!.add(
          TesourariaItemDetalhe(
            tipo: 'Pago',
            descricao: _nomeFornecedor(c),
            valor: v,
            referencia: '${c.numeroParcela} · ${c.numeroNota ?? 'NF-e'}',
            realizado: true,
          ),
        );
        continue;
      }
      final venc = _data(c.dataVencimento.toLocal());
      if (venc.isBefore(inicio) || venc.isAfter(fim)) continue;
      final v = c.valorParcela;
      if (v <= 0.001) continue;
      addPrevisto(venc, v, false, 'pagar');
      itens[venc]!.add(
        TesourariaItemDetalhe(
          tipo: 'A pagar',
          descricao: _nomeFornecedor(c),
          valor: v,
          referencia: '${c.numeroParcela} · ${c.numeroNota ?? 'NF-e'}',
        ),
      );
    }

    for (final r in _listarRecebimentos(objectBox)) {
      final dia = _data(r.data.toLocal());
      if (dia.isBefore(inicio) || dia.isAfter(fim)) continue;
      if (r.valorTotal <= 0.001) continue;
      addRealizado(dia, r.valorTotal, true, 'recebimento');
      itens[dia]!.add(
        TesourariaItemDetalhe(
          tipo: 'Recebido',
          descricao: r.cliente.target?.nomeRazao ?? 'Cliente',
          valor: r.valorTotal,
          referencia: r.formaPagamento,
          realizado: true,
        ),
      );
    }

    final linhas = dias.map((d) => mapa[d]!).toList();
    var entPrev = 0.0;
    var saiPrev = 0.0;
    var entReal = 0.0;
    var saiReal = 0.0;
    for (final l in linhas) {
      if (!l.dia.isBefore(hoje)) {
        entPrev += l.entradasPrevistas;
        saiPrev += l.saidasPrevistas;
      }
      if (!l.dia.isAfter(hoje)) {
        entReal += l.entradasRealizadas;
        saiReal += l.saidasRealizadas;
      }
    }

    return TesourariaSemanalSnapshot(
      dias: linhas,
      itensPorDia: itens,
      totalEntradasPrevistas: entPrev,
      totalSaidasPrevistas: saiPrev,
      totalEntradasRealizadas: entReal,
      totalSaidasRealizadas: saiReal,
    );
  }

  static List<RecebimentoFiado> _listarRecebimentos(ObjectBox objectBox) {
    return objectBox.recebimentoFiadoBox.getAll();
  }

  static String _nomeFornecedor(ContaPagar c) {
    final f = c.fornecedor.target;
    if (f == null) return 'Fornecedor';
    final nome = f.nomeFantasia.trim().isNotEmpty
        ? f.nomeFantasia
        : f.razaoSocial;
    return nome.trim().isEmpty ? 'Fornecedor' : nome;
  }
}

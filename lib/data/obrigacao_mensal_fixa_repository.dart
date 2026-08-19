import '../model/obrigacao_mensal_fixa.dart';
import '../objectbox.g.dart';
import 'conta_pagar_repository.dart';
import 'objectbox.dart';

/// Cadastro de obrigacoes fixas e geracao de [ContaPagar].
///
/// Templates ficam no ObjectBox do servidor (PC1). As contas geradas usam
/// [ContaPagar] (ja sincronizado). Idempotencia via [ContaPagar.numeroNota]:
/// - mensal: `FIXA#{id}#{yyyyMM}`
/// - semanal: `FIXA#{id}#W{yyyyMMdd}` (segunda da semana)
/// - anual: `FIXA#{id}#A{yyyy}`
class ObrigacaoMensalFixaRepository {
  ObrigacaoMensalFixaRepository(this._db);

  final ObjectBox _db;

  Box<ObrigacaoMensalFixa> get _box => _db.obrigacaoMensalFixaBox;

  ContaPagarRepository get _contas => ContaPagarRepository(_db);

  static const _nomesDiaSemana = [
    '',
    'Segunda',
    'Terca',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sabado',
    'Domingo',
  ];

  static const _nomesMes = [
    '',
    'Janeiro',
    'Fevereiro',
    'Marco',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  static String nomeDiaSemana(int weekday) {
    final d = weekday.clamp(1, 7);
    return _nomesDiaSemana[d];
  }

  static String nomeMes(int mes) {
    final m = mes.clamp(1, 12);
    return _nomesMes[m];
  }

  static String resumoVencimento(ObrigacaoMensalFixa o) {
    final p = ObrigacaoPeriodicidade.normalizar(o.periodicidade);
    switch (p) {
      case ObrigacaoPeriodicidade.semanal:
        return 'Toda ${nomeDiaSemana(o.diaVencimento).toLowerCase()}';
      case ObrigacaoPeriodicidade.anual:
        return 'Todo ano em ${o.diaVencimento.toString().padLeft(2, '0')}/'
            '${o.mesVencimento.toString().padLeft(2, '0')}';
      default:
        return 'Todo mes no dia ${o.diaVencimento}';
    }
  }

  static bool isChaveFixa(String? numeroNota) {
    final n = (numeroNota ?? '').trim();
    return n.startsWith('FIXA#');
  }

  static DateTime segundaDaSemana(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - 1));
  }

  static String chaveMensal(int obrigacaoId, int ano, int mes) {
    final mm = mes.toString().padLeft(2, '0');
    return 'FIXA#$obrigacaoId#$ano$mm';
  }

  static String chaveSemanal(int obrigacaoId, DateTime segunda) {
    final y = segunda.year.toString().padLeft(4, '0');
    final m = segunda.month.toString().padLeft(2, '0');
    final d = segunda.day.toString().padLeft(2, '0');
    return 'FIXA#$obrigacaoId#W$y$m$d';
  }

  static String chaveAnual(int obrigacaoId, int ano) =>
      'FIXA#$obrigacaoId#A$ano';

  static DateTime vencimentoNoMes({
    required int ano,
    required int mes,
    required int diaVencimento,
  }) {
    final ultimo = DateTime(ano, mes + 1, 0).day;
    final dia = diaVencimento.clamp(1, ultimo);
    return DateTime(ano, mes, dia);
  }

  List<ObrigacaoMensalFixa> listar({bool somenteAtivas = false}) {
    final todos = _box.getAll();
    final lista = somenteAtivas
        ? todos.where((o) => o.ativo).toList()
        : List<ObrigacaoMensalFixa>.from(todos);
    lista.sort((a, b) {
      final byPer = ObrigacaoPeriodicidade.normalizar(a.periodicidade)
          .compareTo(ObrigacaoPeriodicidade.normalizar(b.periodicidade));
      if (byPer != 0) return byPer;
      final byDia = a.diaVencimento.compareTo(b.diaVencimento);
      if (byDia != 0) return byDia;
      return a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase());
    });
    return lista;
  }

  ObrigacaoMensalFixa? obterPorId(int id) => _box.get(id);

  Future<ObrigacaoMensalFixa> salvar({
    int id = 0,
    required String descricao,
    required double valor,
    String periodicidade = ObrigacaoPeriodicidade.mensal,
    required int diaVencimento,
    int mesVencimento = 1,
    String cnpj = '',
    bool ativo = true,
  }) async {
    final nome = descricao.trim();
    if (nome.isEmpty) {
      throw ArgumentError('Informe a descricao da obrigacao.');
    }
    if (valor <= 0) {
      throw ArgumentError('Valor deve ser positivo.');
    }
    final periodo = ObrigacaoPeriodicidade.normalizar(periodicidade);
    late final int dia;
    late final int mes;
    switch (periodo) {
      case ObrigacaoPeriodicidade.semanal:
        if (diaVencimento < 1 || diaVencimento > 7) {
          throw ArgumentError('Informe o dia da semana (1=seg … 7=dom).');
        }
        dia = diaVencimento;
        mes = 1;
      case ObrigacaoPeriodicidade.anual:
        if (diaVencimento < 1 || diaVencimento > 28) {
          throw ArgumentError('Dia do vencimento anual deve ser 1–28.');
        }
        if (mesVencimento < 1 || mesVencimento > 12) {
          throw ArgumentError('Mes do vencimento anual deve ser 1–12.');
        }
        dia = diaVencimento;
        mes = mesVencimento;
      default:
        if (diaVencimento < 1 || diaVencimento > 28) {
          throw ArgumentError('Dia do vencimento mensal deve ser 1–28.');
        }
        dia = diaVencimento;
        mes = 1;
    }
    final doc = cnpj.replaceAll(RegExp(r'\D'), '');

    ObrigacaoMensalFixa item;
    if (id > 0) {
      final existente = _box.get(id);
      if (existente == null) {
        throw StateError('Obrigacao $id nao encontrada.');
      }
      existente.descricao = nome;
      existente.valor = valor;
      existente.periodicidade = periodo;
      existente.diaVencimento = dia;
      existente.mesVencimento = mes;
      existente.cnpj = doc;
      existente.ativo = ativo;
      item = existente;
    } else {
      item = ObrigacaoMensalFixa(
        descricao: nome,
        valor: valor,
        periodicidade: periodo,
        diaVencimento: dia,
        mesVencimento: mes,
        cnpj: doc,
        ativo: ativo,
      );
    }
    final novoId = _box.put(item);
    item.id = novoId;

    if (item.ativo) {
      await _gerarPendenciasDe(item, DateTime.now());
    }
    return item;
  }

  bool remover(int id) => _box.remove(id);

  bool _jaExisteContaComChave(String chave) {
    for (final c in _db.contaPagarBox.getAll()) {
      if ((c.numeroNota ?? '').trim() == chave) return true;
    }
    return false;
  }

  Future<int> _criarSeNovo({
    required ObrigacaoMensalFixa o,
    required String chave,
    required DateTime vencimento,
    required DateTime emissao,
  }) async {
    if (_jaExisteContaComChave(chave)) return 0;
    await _contas.criarManual(
      nomeFornecedor: o.descricao,
      cnpj: o.cnpj.isEmpty ? null : o.cnpj,
      valor: o.valor,
      vencimento: vencimento,
      numeroParcela: 'FIXA',
      emissao: emissao,
      observacaoNota: chave,
    );
    return 1;
  }

  Future<int> _gerarMes(ObrigacaoMensalFixa o, int ano, int mes) {
    final chave = chaveMensal(o.id, ano, mes);
    final venc = vencimentoNoMes(
      ano: ano,
      mes: mes,
      diaVencimento: o.diaVencimento,
    );
    return _criarSeNovo(
      o: o,
      chave: chave,
      vencimento: venc,
      emissao: DateTime(ano, mes, 1),
    );
  }

  Future<int> _gerarSemana(ObrigacaoMensalFixa o, DateTime segunda) {
    final weekday = o.diaVencimento.clamp(1, 7);
    final venc = segunda.add(Duration(days: weekday - 1));
    final chave = chaveSemanal(o.id, segunda);
    return _criarSeNovo(
      o: o,
      chave: chave,
      vencimento: venc,
      emissao: segunda,
    );
  }

  Future<int> _gerarAno(ObrigacaoMensalFixa o, int ano) {
    final mes = o.mesVencimento.clamp(1, 12);
    final chave = chaveAnual(o.id, ano);
    final venc = vencimentoNoMes(
      ano: ano,
      mes: mes,
      diaVencimento: o.diaVencimento,
    );
    return _criarSeNovo(
      o: o,
      chave: chave,
      vencimento: venc,
      emissao: DateTime(ano, mes, 1),
    );
  }

  Future<int> _gerarPendenciasDe(ObrigacaoMensalFixa o, DateTime agora) async {
    final p = ObrigacaoPeriodicidade.normalizar(o.periodicidade);
    switch (p) {
      case ObrigacaoPeriodicidade.semanal:
        final seg = segundaDaSemana(agora);
        var n = await _gerarSemana(o, seg);
        if (agora.weekday <= 2) {
          n += await _gerarSemana(o, seg.subtract(const Duration(days: 7)));
        }
        return n;
      case ObrigacaoPeriodicidade.anual:
        var n = await _gerarAno(o, agora.year);
        if (agora.month == 1 && agora.day <= 15) {
          n += await _gerarAno(o, agora.year - 1);
        }
        return n;
      default:
        var n = await _gerarMes(o, agora.year, agora.month);
        if (agora.day <= 5) {
          final ant = DateTime(agora.year, agora.month - 1, 1);
          n += await _gerarMes(o, ant.year, ant.month);
        }
        return n;
    }
  }

  /// Gera pendencias recentes de todas as obrigacoes ativas (idempotente).
  Future<int> gerarPendenciasRecentes() async {
    final agora = DateTime.now();
    var total = 0;
    for (final o in listar(somenteAtivas: true)) {
      total += await _gerarPendenciasDe(o, agora);
    }
    return total;
  }

  /// Compat: gera so mensais do mes informado.
  Future<int> gerarParaMes({required int ano, required int mes}) async {
    var criadas = 0;
    for (final o in listar(somenteAtivas: true)) {
      if (ObrigacaoPeriodicidade.normalizar(o.periodicidade) !=
          ObrigacaoPeriodicidade.mensal) {
        continue;
      }
      criadas += await _gerarMes(o, ano, mes);
    }
    return criadas;
  }

  Map<String, dynamic> paraMap(ObrigacaoMensalFixa o) => {
        'id': o.id,
        'descricao': o.descricao,
        'valor': o.valor,
        'periodicidade': ObrigacaoPeriodicidade.normalizar(o.periodicidade),
        'diaVencimento': o.diaVencimento,
        'mesVencimento': o.mesVencimento,
        'cnpj': o.cnpj,
        'ativo': o.ativo,
        'criadoEm': o.criadoEm.toUtc().toIso8601String(),
      };

  ObrigacaoMensalFixa deMap(Map<String, dynamic> m) => ObrigacaoMensalFixa(
        id: (m['id'] as num?)?.toInt() ?? 0,
        descricao: (m['descricao'] ?? '').toString(),
        valor: (m['valor'] as num?)?.toDouble() ?? 0,
        periodicidade: ObrigacaoPeriodicidade.normalizar(
          (m['periodicidade'] ?? '').toString(),
        ),
        diaVencimento: (m['diaVencimento'] as num?)?.toInt() ?? 10,
        mesVencimento: (m['mesVencimento'] as num?)?.toInt() ?? 1,
        cnpj: (m['cnpj'] ?? '').toString(),
        ativo: m['ativo'] != false,
        criadoEm: DateTime.tryParse((m['criadoEm'] ?? '').toString())?.toUtc(),
      );
}

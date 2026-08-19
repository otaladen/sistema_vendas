import 'dart:convert';

import '../domain/lote_validade_config.dart';
import '../model/lote_produto.dart';
import '../model/produto.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Snapshot de consumo FEFO para gravar em [ItemVenda.loteConsumosJson].
class LoteConsumoSnapshot {
  const LoteConsumoSnapshot({
    required this.loteId,
    required this.numeroLote,
    this.dataValidade,
    required this.quantidade,
  });

  final int loteId;
  final String numeroLote;
  final DateTime? dataValidade;
  final int quantidade;

  Map<String, dynamic> toJson() => {
        'loteId': loteId,
        'numeroLote': numeroLote,
        if (dataValidade != null)
          'dataValidade': dataValidade!.toUtc().toIso8601String(),
        'qtd': quantidade,
      };

  factory LoteConsumoSnapshot.fromJson(Map<String, dynamic> m) =>
      LoteConsumoSnapshot(
        loteId: (m['loteId'] as num?)?.toInt() ?? 0,
        numeroLote: (m['numeroLote'] ?? '').toString(),
        dataValidade:
            DateTime.tryParse((m['dataValidade'] ?? '').toString())?.toUtc(),
        quantidade: (m['qtd'] as num?)?.toInt() ?? 0,
      );

  static String encodeList(List<LoteConsumoSnapshot> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<LoteConsumoSnapshot> decodeList(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];
    try {
      final decoded = jsonDecode(t);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (e) => LoteConsumoSnapshot.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class LoteProdutoRepository {
  LoteProdutoRepository(this._db);

  final ObjectBox _db;

  Box<LoteProduto> get _box => _db.loteProdutoBox;

  List<LoteProduto> listarPorProduto(int produtoId) {
    if (produtoId <= 0) return const [];
    return _box
        .query(LoteProduto_.produto.equals(produtoId))
        .build()
        .find()
      ..sort((a, b) {
        final va = a.dataValidade;
        final vb = b.dataValidade;
        if (va == null && vb == null) {
          return a.dataEntrada.compareTo(b.dataEntrada);
        }
        if (va == null) return 1;
        if (vb == null) return -1;
        final c = va.compareTo(vb);
        if (c != 0) return c;
        return a.dataEntrada.compareTo(b.dataEntrada);
      });
  }

  List<LoteProduto> listarTodos() => _box.getAll();

  LoteProduto? obterPorId(int id) => id > 0 ? _box.get(id) : null;

  List<LoteProduto> lotesVendaveisFefo(int produtoId) {
    return listarPorProduto(produtoId).where((l) => l.vendavel).toList();
  }

  int somaQuantidadeAtiva(int produtoId) {
    var s = 0;
    for (final l in listarPorProduto(produtoId)) {
      if (l.ativo && l.quantidadeEstoque > 0 && !l.vencido) {
        s += l.quantidadeEstoque;
      }
    }
    return s;
  }

  int gravar(LoteProduto lote, {bool notificar = true}) {
    final id = _box.put(lote);
    if (notificar) {
      notificarAlteracaoParaRede(entidade: 'lote_produto', entidadeId: id);
    }
    return id;
  }

  /// Cria ou incrementa lote pelo numero (mesmo produto + mesmo numero + mesma validade).
  LoteProduto registrarEntrada({
    required Produto produto,
    required int quantidade,
    String numeroLote = '',
    DateTime? dataValidade,
    bool notificar = true,
  }) {
    if (quantidade <= 0) {
      throw ArgumentError('Quantidade do lote deve ser > 0.');
    }
    final numNorm = numeroLote.trim().isEmpty
        ? LoteProduto.numeroSemLote
        : numeroLote.trim().toUpperCase();
    final existentes = listarPorProduto(produto.id);
    LoteProduto? alvo;
    for (final l in existentes) {
      if (!l.ativo) continue;
      if (l.numeroLote.toUpperCase() != numNorm) continue;
      final lv = l.dataValidade;
      if (dataValidade == null && lv == null) {
        alvo = l;
        break;
      }
      if (dataValidade != null && lv != null) {
        final a = DateTime(dataValidade.year, dataValidade.month, dataValidade.day);
        final b = DateTime(lv.year, lv.month, lv.day);
        if (a == b) {
          alvo = l;
          break;
        }
      }
    }
    if (alvo != null) {
      alvo.quantidadeEstoque += quantidade;
      if (alvo.vencido) {
        // Reentrada em lote vencido: mantem inativo ate operador reativar.
      } else {
        alvo.ativo = true;
      }
      gravar(alvo, notificar: notificar);
      return alvo;
    }
    final novo = LoteProduto(
      numeroLote: numNorm,
      dataValidade: dataValidade?.toUtc(),
      quantidadeEstoque: quantidade,
      dataEntrada: DateTime.now().toUtc(),
      ativo: true,
    );
    novo.produto.target = produto;
    gravar(novo, notificar: notificar);
    return novo;
  }

  /// Garante lote SEM-LOTE cobrindo estoque fisico sem rastreio.
  void garantirMigracaoSemLote(Produto produto, {bool notificar = true}) {
    if (!produto.controlaLoteValidade || produto.id <= 0) return;
    final lotes = listarPorProduto(produto.id);
    final somaAtiva = lotes
        .where((l) => l.ativo && l.quantidadeEstoque > 0)
        .fold<int>(0, (a, b) => a + b.quantidadeEstoque);
    final fisico = produto.estoqueReal;
    if (fisico <= 0) return;
    if (somaAtiva >= fisico) return;
    final falta = fisico - somaAtiva;
    registrarEntrada(
      produto: produto,
      quantidade: falta,
      numeroLote: LoteProduto.numeroSemLote,
      dataValidade: null,
      notificar: notificar,
    );
  }

  int desativarVencidos({bool notificar = true}) {
    var n = 0;
    final todos = _box.getAll();
    for (final l in todos) {
      if (!l.ativo) continue;
      if (!l.vencido) continue;
      l.ativo = false;
      gravar(l, notificar: notificar);
      n++;
    }
    return n;
  }

  ContagemValidadeLotes contarSemaforo() {
    var verde = 0, amarelo = 0, laranja = 0, vermelho = 0, semVal = 0;
    for (final l in _box.getAll()) {
      if (!l.ativo || l.quantidadeEstoque <= 0) continue;
      final s = LoteValidadeSemaforoUtil.deDiasRestantes(l.diasParaVencer);
      switch (s) {
        case LoteValidadeSemaforo.verde:
          verde++;
        case LoteValidadeSemaforo.amarelo:
          amarelo++;
        case LoteValidadeSemaforo.laranja:
          laranja++;
        case LoteValidadeSemaforo.vermelho:
          vermelho++;
        case LoteValidadeSemaforo.semValidade:
          semVal++;
      }
    }
    return ContagemValidadeLotes(
      verde: verde,
      amarelo: amarelo,
      laranja: laranja,
      vermelho: vermelho,
      semValidade: semVal,
    );
  }
}

class ContagemValidadeLotes {
  const ContagemValidadeLotes({
    required this.verde,
    required this.amarelo,
    required this.laranja,
    required this.vermelho,
    required this.semValidade,
  });

  final int verde;
  final int amarelo;
  final int laranja;
  final int vermelho;
  final int semValidade;

  int get criticosOuVencidos => laranja + vermelho;
}

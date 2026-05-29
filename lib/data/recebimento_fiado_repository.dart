import '../domain/recebimento_fiado_codec.dart';
import '../model/recebimento_fiado.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';
import 'titulo_receber_repository.dart';

class RecebimentoFiadoRepository {
  RecebimentoFiadoRepository(this._db, this._titulos);

  final ObjectBox _db;
  final TituloReceberRepository _titulos;

  RecebimentoFiado? obterPorId(int id) {
    if (id <= 0) return null;
    return _db.recebimentoFiadoBox.get(id);
  }

  /// Recebimentos no intervalo (para fechamento do caixa).
  List<RecebimentoFiado> listarNoPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) {
    final inicioUtc = inicio.toUtc();
    final fimUtc = fim.toUtc();
    final q = _db.recebimentoFiadoBox.query().build();
    try {
      return q.find().where((r) {
        final d = r.data.toUtc();
        return !d.isBefore(inicioUtc) && !d.isAfter(fimUtc);
      }).toList();
    } finally {
      q.close();
    }
  }

  List<RecebimentoFiado> listarPorCliente(int clienteId) {
    if (clienteId <= 0) return [];
    final q = _db.recebimentoFiadoBox
        .query(RecebimentoFiado_.cliente.equals(clienteId))
        .order(RecebimentoFiado_.data, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Aplica valor em titulos em aberto (vencimento mais antigo primeiro).
  int registrarRecebimentoFifo({
    required int clienteId,
    required double valorRecebido,
    required String formaPagamento,
    String observacao = '',
  }) {
    if (clienteId <= 0) {
      throw ArgumentError('Cliente invalido.');
    }
    if (valorRecebido <= 0.001) {
      throw ArgumentError('Informe o valor recebido.');
    }
    final forma =
        formaPagamento.trim().isEmpty ? 'dinheiro' : formaPagamento.trim();

    return _db.store.runInTransaction(TxMode.write, () {
      var restante = valorRecebido;
      final alocacoes = <RecebimentoFiadoAlocacao>[];
      final abertos = _titulos.listarAbertosPorCliente(clienteId);

      for (final t in abertos) {
        if (restante <= 0.001) break;
        final abate = restante < t.saldo ? restante : t.saldo;
        _titulos.abaterSaldo(t.id, abate);
        alocacoes.add(RecebimentoFiadoAlocacao(tituloId: t.id, valor: abate));
        restante -= abate;
      }

      if (alocacoes.isEmpty) {
        throw StateError('Cliente sem titulos em aberto para receber.');
      }

      final somaAlocada = alocacoes.fold<double>(0, (s, a) => s + a.valor);
      final rec = RecebimentoFiado(
        valorTotal: somaAlocada,
        formaPagamento: forma,
        observacao: observacao.trim(),
        alocacoesJson: RecebimentoFiadoCodec.encode(alocacoes),
      );
      rec.cliente.targetId = clienteId;
      final id = _db.recebimentoFiadoBox.put(rec);
      notificarAlteracaoParaRede(
        entidade: 'recebimento_fiado',
        entidadeId: id,
      );
      return id;
    });
  }

  /// Quita um titulo especifico (total ou parcial).
  int registrarRecebimentoTitulo({
    required int tituloId,
    required double valorRecebido,
    required String formaPagamento,
    String observacao = '',
  }) {
    if (valorRecebido <= 0.001) {
      throw ArgumentError('Informe o valor recebido.');
    }
    final forma = formaPagamento.trim().isEmpty ? 'dinheiro' : formaPagamento.trim();

    return _db.store.runInTransaction(TxMode.write, () {
      final titulo = _titulos.obterPorId(tituloId);
      if (titulo == null) {
        throw StateError('Titulo nao encontrado.');
      }
      if (!titulo.emAberto) {
        throw StateError('Titulo nao esta em aberto.');
      }
      final abate = valorRecebido > titulo.saldo ? titulo.saldo : valorRecebido;
      _titulos.abaterSaldo(tituloId, abate);

      final clienteId = titulo.cliente.targetId;
      final rec = RecebimentoFiado(
        valorTotal: abate,
        formaPagamento: forma,
        observacao: observacao.trim(),
        alocacoesJson: RecebimentoFiadoCodec.encode([
          RecebimentoFiadoAlocacao(tituloId: tituloId, valor: abate),
        ]),
      );
      rec.cliente.targetId = clienteId;
      final id = _db.recebimentoFiadoBox.put(rec);
      notificarAlteracaoParaRede(
        entidade: 'recebimento_fiado',
        entidadeId: id,
      );
      return id;
    });
  }
}

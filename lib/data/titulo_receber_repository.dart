import '../domain/limite_credito_helper.dart';
import '../domain/plano_fiado.dart';
import '../domain/titulo_receber_catalogo.dart';
import '../model/titulo_receber.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class TituloReceberResumoLinha {
  const TituloReceberResumoLinha({
    required this.titulo,
    required this.numeroOrcamento,
    required this.nomeCliente,
    required this.diasAtraso,
  });

  final TituloReceber titulo;
  final int numeroOrcamento;
  final String nomeCliente;
  final int diasAtraso;
}

class TituloReceberRepository {
  TituloReceberRepository(this._db);

  final ObjectBox _db;

  TituloReceber? obterPorId(int id) => _db.tituloReceberBox.get(id);

  bool existeParaVenda(int vendaId) {
    if (vendaId <= 0) return false;
    final q = _db.tituloReceberBox
        .query(TituloReceber_.venda.equals(vendaId))
        .build();
    try {
      return q.findFirst() != null;
    } finally {
      q.close();
    }
  }

  List<TituloReceber> listarPorVenda(int vendaId) {
    if (vendaId <= 0) return [];
    final q = _db.tituloReceberBox
        .query(TituloReceber_.venda.equals(vendaId))
        .order(TituloReceber_.numeroParcela)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<TituloReceber> listarAbertosPorCliente(int clienteId) {
    if (clienteId <= 0) return [];
    final q = _db.tituloReceberBox
        .query(
          TituloReceber_.cliente.equals(clienteId) &
              TituloReceber_.status.equals(TituloReceberCatalogo.aberto),
        )
        .order(TituloReceber_.vencimento)
        .build();
    try {
      return q.find().where((t) => t.saldo > 0.001).toList();
    } finally {
      q.close();
    }
  }

  List<TituloReceberResumoLinha> listarTodosAbertos({bool somenteVencidos = false}) {
    final q = _db.tituloReceberBox
        .query(TituloReceber_.status.equals(TituloReceberCatalogo.aberto))
        .order(TituloReceber_.vencimento)
        .build();
    try {
      final hoje = DateTime.now().toUtc();
      final out = <TituloReceberResumoLinha>[];
      for (final t in q.find()) {
        if (t.saldo <= 0.001) continue;
        t.cliente.target;
        t.venda.target;
        final venc = DateTime.utc(
          t.vencimento.year,
          t.vencimento.month,
          t.vencimento.day,
        );
        final hojeD = DateTime.utc(hoje.year, hoje.month, hoje.day);
        final diasAtraso = hojeD.difference(venc).inDays;
        if (somenteVencidos && diasAtraso <= 0) continue;
        final cliente = t.cliente.target;
        final venda = t.venda.target;
        out.add(
          TituloReceberResumoLinha(
            titulo: t,
            numeroOrcamento: venda?.numeroOrcamento ?? 0,
            nomeCliente: cliente?.nomeRazao ?? '-',
            diasAtraso: diasAtraso > 0 ? diasAtraso : 0,
          ),
        );
      }
      return out;
    } finally {
      q.close();
    }
  }

  double saldoAbertoCliente(int clienteId) {
    return listarAbertosPorCliente(clienteId)
        .fold<double>(0, (s, t) => s + t.saldo);
  }

  /// Todos os títulos do cliente (abertos e quitados), vencimento ascendente.
  List<TituloReceber> listarTodosPorCliente(int clienteId) {
    if (clienteId <= 0) return [];
    final q = _db.tituloReceberBox
        .query(TituloReceber_.cliente.equals(clienteId))
        .order(TituloReceber_.vencimento)
        .build();
    try {
      final lista = q.find();
      for (final t in lista) {
        t.venda.target;
      }
      return lista;
    } finally {
      q.close();
    }
  }

  List<TituloReceber> listarQuitadosPorCliente(int clienteId, {int limite = 30}) {
    if (clienteId <= 0) return [];
    final q = _db.tituloReceberBox
        .query(
          TituloReceber_.cliente.equals(clienteId) &
              TituloReceber_.status.equals(TituloReceberCatalogo.quitado),
        )
        .order(TituloReceber_.dataQuitacao, flags: Order.descending)
        .build();
    try {
      final lista = q.find();
      for (final t in lista) {
        t.venda.target;
      }
      return lista.take(limite).toList();
    } finally {
      q.close();
    }
  }

  void gerarTitulosDaVenda(Venda venda) {
    final valorFiado = LimiteCreditoHelper.valorFiadoNaVenda(venda);
    if (valorFiado <= 0.001) return;
    if (existeParaVenda(venda.id)) return;

    final clienteId = venda.cliente.targetId;
    if (clienteId <= 0) {
      throw StateError('Venda fiado sem cliente para gerar titulos.');
    }

    var parcelas = PlanoFiadoCodec.decode(venda.planoFiadoJson);
    if (!PlanoFiadoCodec.validarContraValor(parcelas, valorFiado)) {
      parcelas = PlanoFiadoCodec.gerarParcelasIguais(
        valorTotal: valorFiado,
        quantidade: 1,
        primeiroVencimento: venda.data.toUtc().add(const Duration(days: 30)),
      );
    }

    final totalPar = parcelas.length;
    for (final p in parcelas) {
      final titulo = TituloReceber(
        numeroParcela: p.numero,
        totalParcelas: totalPar,
        valorOriginal: p.valor,
        saldo: p.valor,
        status: TituloReceberCatalogo.aberto,
        vencimento: p.vencimento.toUtc(),
      );
      titulo.cliente.targetId = clienteId;
      titulo.venda.targetId = venda.id;
      _db.tituloReceberBox.put(titulo);
    }
    notificarAlteracaoParaRede(
      entidade: 'titulo_receber',
      entidadeId: 0,
    );
  }

  void cancelarPorVenda(int vendaId) {
    final titulos = listarPorVenda(vendaId);
    if (titulos.isEmpty) return;
    final agora = DateTime.now().toUtc();
    for (final t in titulos) {
      if (t.status == TituloReceberCatalogo.quitado) continue;
      t.status = TituloReceberCatalogo.cancelado;
      t.saldo = 0;
      t.dataQuitacao = agora;
      _db.tituloReceberBox.put(t);
    }
    notificarAlteracaoParaRede(
      entidade: 'titulo_receber',
      entidadeId: 0,
    );
  }

  void abaterSaldo(int tituloId, double valor) {
    final t = obterPorId(tituloId);
    if (t == null) {
      throw StateError('Titulo $tituloId nao encontrado.');
    }
    if (t.status != TituloReceberCatalogo.aberto) {
      throw StateError('Titulo $tituloId nao esta em aberto.');
    }
    if (valor <= 0) {
      throw ArgumentError('Valor de abatimento invalido.');
    }
    if (valor > t.saldo + 0.02) {
      throw StateError(
        'Valor R\$ ${valor.toStringAsFixed(2)} maior que saldo '
        'R\$ ${t.saldo.toStringAsFixed(2)}.',
      );
    }
    t.saldo = (t.saldo - valor).clamp(0, double.infinity).toDouble();
    if (t.saldo <= 0.001) {
      t.saldo = 0;
      t.status = TituloReceberCatalogo.quitado;
      t.dataQuitacao = DateTime.now().toUtc();
    }
    _db.tituloReceberBox.put(t);
    notificarAlteracaoParaRede(
      entidade: 'titulo_receber',
      entidadeId: tituloId,
    );
  }

  /// Vendas finalizadas fiado sem titulos (legado).
  /// Roda no maximo uma vez por sessao do app (evita ANR no login do celular).
  static bool _migracaoLegadoFeitaNestaSessao = false;

  void migrarTitulosLegadoSeNecessario({bool forcar = false}) {
    if (_migracaoLegadoFeitaNestaSessao && !forcar) return;
    _migracaoLegadoFeitaNestaSessao = true;
    final q = _db.vendaBox
        .query(
          Venda_.status.equals('finalizada') &
              Venda_.cancelada.equals(false),
        )
        .build();
    try {
      for (final v in q.find()) {
        final fiado = LimiteCreditoHelper.valorFiadoNaVenda(v);
        if (fiado <= 0.001) continue;
        if (existeParaVenda(v.id)) continue;
        if (v.planoFiadoJson.trim().isEmpty) {
          v.planoFiadoJson = PlanoFiadoCodec.encode(
            PlanoFiadoCodec.gerarParcelasIguais(
              valorTotal: fiado,
              quantidade: 1,
              primeiroVencimento: v.data.toUtc().add(const Duration(days: 30)),
            ),
          );
          _db.vendaBox.put(v);
        }
        gerarTitulosDaVenda(v);
      }
    } finally {
      q.close();
    }
  }
}

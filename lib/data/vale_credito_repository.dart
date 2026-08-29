import '../domain/vale_credito.dart';
import '../model/uso_vale_credito.dart';
import '../model/vale_credito.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Emissao e resgate dos vales de credito gerados por devolucao.
class ValeCreditoRepository {
  ValeCreditoRepository(this._db);

  final ObjectBox _db;

  /// Prazo padrao quando a emissao nao informa outro.
  static const validadeDiasPadrao = 90;

  Box<ValeCredito> get _box => _db.valeCreditoBox;
  Box<UsoValeCredito> get _usoBox => _db.usoValeCreditoBox;

  ValeCredito? obterPorId(int id) => id > 0 ? _box.get(id) : null;

  ValeCredito? buscarPorCodigo(String codigo) {
    final n = ValeCreditoCodigo.normalizar(codigo);
    if (n.isEmpty) return null;
    final q = _box.query(ValeCredito_.codigo.equals(n)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  List<ValeCredito> listarPorCliente(int clienteId) {
    if (clienteId <= 0) return const [];
    final q = _box.query(ValeCredito_.cliente.equals(clienteId)).build();
    try {
      final itens = q.find();
      itens.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
      return itens;
    } finally {
      q.close();
    }
  }

  /// Vales do cliente que ainda tem saldo para gastar hoje.
  List<ValeCredito> listarGastaveisDoCliente(int clienteId) =>
      listarPorCliente(clienteId).where((v) => situacao(v).gastavel).toList();

  List<ValeCredito> listarTodos() {
    final itens = _box.getAll();
    itens.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));
    return itens;
  }

  double saldo(ValeCredito v) => ValeCreditoRegras.saldo(
        valorOriginal: v.valorOriginal,
        valorUtilizado: v.valorUtilizado,
      );

  ValeCreditoSituacao situacao(ValeCredito v, {DateTime? agora}) =>
      ValeCreditoRegras.situacao(
        valorOriginal: v.valorOriginal,
        valorUtilizado: v.valorUtilizado,
        cancelado: v.cancelado,
        validade: v.dataValidade,
        agora: agora,
      );

  ValeCreditoAvaliacao avaliar(
    ValeCredito v, {
    required double totalAPagar,
    DateTime? agora,
  }) =>
      ValeCreditoRegras.avaliarResgate(
        valorOriginal: v.valorOriginal,
        valorUtilizado: v.valorUtilizado,
        cancelado: v.cancelado,
        totalAPagar: totalAPagar,
        validade: v.dataValidade,
        agora: agora,
      );

  ValeCredito emitir({
    required double valor,
    required String emitidoPor,
    int vendaOrigemId = 0,
    int registroDevolucaoId = 0,
    int clienteId = 0,
    int numeroVendaOrigem = 0,
    String observacao = '',
    int? validadeDias = validadeDiasPadrao,
  }) {
    if (!ValeCreditoValor.positivo(valor)) {
      throw StateError('Valor do vale precisa ser maior que zero.');
    }

    final vale = _db.store.runInTransaction(TxMode.write, () {
      final v = ValeCredito(
        codigo: _gerarCodigoLivre(),
        valorOriginal: valor,
        emitidoPor: emitidoPor.trim().isEmpty ? 'sistema' : emitidoPor.trim(),
        observacao: observacao.trim(),
        numeroVendaOrigem: numeroVendaOrigem,
        dataValidade: validadeDias == null || validadeDias <= 0
            ? null
            : DateTime.now().add(Duration(days: validadeDias)),
      );
      if (clienteId > 0) v.cliente.targetId = clienteId;
      if (vendaOrigemId > 0) v.vendaOrigem.targetId = vendaOrigemId;
      if (registroDevolucaoId > 0) {
        v.registroDevolucao.targetId = registroDevolucaoId;
      }
      v.id = _box.put(v);
      return v;
    });

    _notificar(vale.id);
    return vale;
  }

  /// Gasta parte (ou todo) o saldo do vale numa venda.
  ///
  /// Revalida o saldo dentro da transacao: entre a tela mostrar o vale e o
  /// caixa fechar, outro terminal pode ter gasto o mesmo codigo.
  UsoValeCredito resgatar({
    required int valeId,
    required double valor,
    required String registradoPor,
    int vendaId = 0,
    int numeroVenda = 0,
    DateTime? agora,
  }) {
    if (!ValeCreditoValor.positivo(valor)) {
      throw StateError('Valor do resgate precisa ser maior que zero.');
    }

    final uso = _db.store.runInTransaction(TxMode.write, () {
      final vale = _box.get(valeId);
      if (vale == null) {
        throw StateError('Vale nao encontrado.');
      }
      final avaliacao = avaliar(vale, totalAPagar: valor, agora: agora);
      if (!avaliacao.podeUsar) {
        throw StateError(avaliacao.motivo);
      }
      if (avaliacao.valorAplicavel + ValeCreditoValor.eps < valor) {
        throw StateError(
          'Saldo do vale e menor que o valor pedido. '
          'Disponivel: ${saldo(vale).toStringAsFixed(2)}.',
        );
      }

      final u = UsoValeCredito(
        valor: valor,
        registradoPor:
            registradoPor.trim().isEmpty ? 'sistema' : registradoPor.trim(),
        numeroVenda: numeroVenda,
      );
      u.vale.target = vale;
      if (vendaId > 0) u.venda.targetId = vendaId;
      u.id = _usoBox.put(u);

      vale.valorUtilizado = ValeCreditoValor.emReais(
        ValeCreditoValor.emCentavos(vale.valorUtilizado) +
            ValeCreditoValor.emCentavos(valor),
      );
      _box.put(vale);
      return u;
    });

    _notificar(valeId);
    return uso;
  }

  /// Devolve ao vale o que foi gasto numa venda que acabou cancelada.
  double estornarUsosDaVenda(int vendaId) {
    if (vendaId <= 0) return 0;
    final afetados = <int>{};
    final total = _db.store.runInTransaction(TxMode.write, () {
      final q = _usoBox.query(UsoValeCredito_.venda.equals(vendaId)).build();
      final usos = q.find();
      q.close();
      var devolvido = 0.0;
      for (final u in usos) {
        final vale = u.vale.target;
        if (vale != null) {
          vale.valorUtilizado = ValeCreditoValor.emReais(
            ValeCreditoValor.emCentavos(vale.valorUtilizado) -
                ValeCreditoValor.emCentavos(u.valor),
          );
          if (vale.valorUtilizado < 0) vale.valorUtilizado = 0;
          _box.put(vale);
          afetados.add(vale.id);
        }
        devolvido += u.valor;
        _usoBox.remove(u.id);
      }
      return devolvido;
    });
    for (final id in afetados) {
      _notificar(id);
    }
    return total;
  }

  ValeCredito cancelar({
    required int valeId,
    required String motivo,
    required String canceladoPor,
  }) {
    final m = motivo.trim();
    if (m.isEmpty) {
      throw StateError('Informe o motivo do cancelamento.');
    }
    final vale = _db.store.runInTransaction(TxMode.write, () {
      final v = _box.get(valeId);
      if (v == null) {
        throw StateError('Vale nao encontrado.');
      }
      if (v.cancelado) {
        throw StateError('Vale ja esta cancelado.');
      }
      v.cancelado = true;
      v.motivoCancelamento = m;
      v.canceladoPor =
          canceladoPor.trim().isEmpty ? 'sistema' : canceladoPor.trim();
      v.dataCancelamento = DateTime.now();
      _box.put(v);
      return v;
    });
    _notificar(vale.id);
    return vale;
  }

  String _gerarCodigoLivre() {
    for (var tentativa = 0; tentativa < 20; tentativa++) {
      final codigo = ValeCreditoCodigo.gerar();
      final q = _box.query(ValeCredito_.codigo.equals(codigo)).build();
      final existe = q.count() > 0;
      q.close();
      if (!existe) return codigo;
    }
    throw StateError('Nao foi possivel gerar um codigo de vale livre.');
  }

  void _notificar(int id) {
    notificarAlteracaoParaRede(entidade: 'vale_credito', entidadeId: id);
  }
}

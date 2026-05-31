import '../data/models/conta_pagar.dart';
import '../model/fornecedor_nfe.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Persistencia e regras de contas a pagar (NF-e + manual).
class ContaPagarRepository {
  ContaPagarRepository(this._db);

  final ObjectBox _db;

  Box<ContaPagar> get _box => _db.contaPagarBox;

  DateTime _somenteData(DateTime d) => DateTime(d.year, d.month, d.day);

  void sincronizarPendenteParaAtrasado() {
    final hoje = _somenteData(DateTime.now());
    for (final c in _box.getAll()) {
      if (c.status != ContaPagarStatus.pendente) continue;
      if (_somenteData(c.dataVencimento).isBefore(hoje)) {
        c.status = ContaPagarStatus.atrasado;
        final id = _box.put(c);
        notificarAlteracaoParaRede(entidade: 'conta_pagar', entidadeId: id);
      }
    }
  }

  List<ContaPagar> listar({String? status, bool ordenarDesc = false}) {
    final Query<ContaPagar> q;
    if (status != null && status.isNotEmpty) {
      q = _box
          .query(ContaPagar_.status.equals(status))
          .order(
            ContaPagar_.dataVencimento,
            flags: ordenarDesc ? Order.descending : 0,
          )
          .build();
    } else {
      q = _box
          .query()
          .order(
            ContaPagar_.dataVencimento,
            flags: ordenarDesc ? Order.descending : 0,
          )
          .build();
    }
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  double somaPorStatus(String status) {
    var t = 0.0;
    for (final c in _box.getAll()) {
      if (c.status == status) t += c.valorParcela;
    }
    return t;
  }

  double somaTotalPago() {
    var t = 0.0;
    for (final c in _box.getAll()) {
      if (c.status == ContaPagarStatus.pago) {
        t += c.valorPago ?? c.valorParcela;
      }
    }
    return t;
  }

  Future<ContaPagar> registrarBaixa({
    required ContaPagar conta,
    required double valorPago,
    required DateTime dataPagamento,
  }) async {
    conta.status = ContaPagarStatus.pago;
    conta.dataPagamento = dataPagamento;
    conta.valorPago = valorPago;
    final id = _box.put(conta);
    notificarAlteracaoParaRede(entidade: 'conta_pagar', entidadeId: id);
    return conta;
  }

  FornecedorNfe _obterOuCriarFornecedor({
    required String nome,
    String? cnpj,
  }) {
    final doc = (cnpj ?? '').replaceAll(RegExp(r'\D'), '');
    if (doc.isNotEmpty) {
      final q = _db.fornecedorNfeBox
          .query(FornecedorNfe_.cnpj.equals(doc))
          .build();
      try {
        final existente = q.findFirst();
        if (existente != null) return existente;
      } finally {
        q.close();
      }
      final f = FornecedorNfe(
        cnpj: doc,
        razaoSocial: nome.trim().isEmpty ? 'Fornecedor' : nome.trim(),
      );
      final id = _db.fornecedorNfeBox.put(f);
      f.id = id;
      return f;
    }

    final chave = 'MANUAL_${nome.trim().toLowerCase().hashCode.abs()}';
    final q = _db.fornecedorNfeBox
        .query(FornecedorNfe_.cnpj.equals(chave))
        .build();
    try {
      final existente = q.findFirst();
      if (existente != null) return existente;
    } finally {
      q.close();
    }
    final f = FornecedorNfe(
      cnpj: chave,
      razaoSocial: nome.trim().isEmpty ? 'Despesa manual' : nome.trim(),
    );
    final id = _db.fornecedorNfeBox.put(f);
    f.id = id;
    return f;
  }

  Future<ContaPagar> criarManual({
    required String nomeFornecedor,
    String? cnpj,
    required double valor,
    required DateTime vencimento,
    String numeroParcela = '001/001',
    DateTime? emissao,
    String? observacaoNota,
  }) async {
    if (valor <= 0) {
      throw ArgumentError('Valor deve ser positivo.');
    }
    final forn = _obterOuCriarFornecedor(
      nome: nomeFornecedor,
      cnpj: cnpj,
    );
    final conta = ContaPagar(
      numeroParcela: numeroParcela,
      dataEmissao: (emissao ?? DateTime.now()).toUtc(),
      dataVencimento: vencimento.toUtc(),
      valorParcela: valor,
      status: ContaPagarStatus.pendente,
      numeroNota: observacaoNota?.trim().isNotEmpty == true
          ? observacaoNota!.trim()
          : 'Manual',
    );
    conta.fornecedor.target = forn;
    final id = _box.put(conta);
    conta.id = id;
    notificarAlteracaoParaRede(entidade: 'conta_pagar', entidadeId: id);
    sincronizarPendenteParaAtrasado();
    return conta;
  }

  bool remover(int id) {
    final ok = _box.remove(id);
    if (ok) {
      registrarDeleteParaRede('conta_pagar', id);
    }
    return ok;
  }
}

import 'dart:convert';

import '../domain/lancamento_funcionario_catalogo.dart';
import '../model/funcionario.dart';
import '../model/lancamento_funcionario.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class LancamentoFuncionarioRepository {
  LancamentoFuncionarioRepository(this._db);

  final ObjectBox _db;

  List<LancamentoFuncionario> listarPorFuncionario(
    int funcionarioId, {
    DateTime? mesReferencia,
  }) {
    if (funcionarioId <= 0) return [];
    var cond = LancamentoFuncionario_.funcionario.equals(funcionarioId);
    if (mesReferencia != null) {
      final inicio = DateTime(mesReferencia.year, mesReferencia.month, 1);
      final fim = DateTime(mesReferencia.year, mesReferencia.month + 1, 0, 23, 59, 59);
      cond = cond &
          LancamentoFuncionario_.data.greaterOrEqualDate(inicio) &
          LancamentoFuncionario_.data.lessOrEqualDate(fim);
    }
    final q = _db.lancamentoFuncionarioBox
        .query(cond)
        .order(LancamentoFuncionario_.data, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<LancamentoFuncionario> listarPorFuncionarioAno(
    int funcionarioId,
    int ano,
  ) {
    if (funcionarioId <= 0) return [];
    final inicio = DateTime(ano, 1, 1);
    final fim = DateTime(ano, 12, 31, 23, 59, 59);
    var cond = LancamentoFuncionario_.funcionario.equals(funcionarioId) &
        LancamentoFuncionario_.data.greaterOrEqualDate(inicio) &
        LancamentoFuncionario_.data.lessOrEqualDate(fim);
    final q = _db.lancamentoFuncionarioBox
        .query(cond)
        .order(LancamentoFuncionario_.data, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  LancamentoFuncionario? obterPorId(int id) =>
      _db.lancamentoFuncionarioBox.get(id);

  int salvar(LancamentoFuncionario lancamento, int funcionarioId) {
    lancamento.funcionario.targetId = funcionarioId;
    final id = _db.lancamentoFuncionarioBox.put(lancamento);
    notificarAlteracaoParaRede(
      entidade: 'lancamento_funcionario',
      entidadeId: id,
    );
    return id;
  }

  void estornar(int id) {
    final l = obterPorId(id);
    if (l == null) return;
    l.estornado = true;
    _db.lancamentoFuncionarioBox.put(l);
    notificarAlteracaoParaRede(
      entidade: 'lancamento_funcionario',
      entidadeId: id,
    );
  }

  void remover(int id) {
    if (_db.lancamentoFuncionarioBox.remove(id)) {
      registrarDeleteParaRede('lancamento_funcionario', id);
    }
  }

  void removerPorFuncionario(int funcionarioId) {
    final lista = listarPorFuncionario(funcionarioId);
    if (lista.isEmpty) return;
    for (final l in lista) {
      registrarDeleteParaRede('lancamento_funcionario', l.id);
    }
    _db.lancamentoFuncionarioBox.removeMany(lista.map((e) => e.id).toList());
    notificarAlteracaoParaRede(
      entidade: 'lancamento_funcionario',
      entidadeId: 0,
    );
  }

  double totalValesAtivos(int funcionarioId, {DateTime? mesReferencia}) {
    return _somarTipo(
      funcionarioId,
      LancamentoFuncionarioCatalogo.vale,
      mesReferencia: mesReferencia,
    );
  }

  double totalDescontosLancados(int funcionarioId, {DateTime? mesReferencia}) {
    return _somarTipo(
      funcionarioId,
      LancamentoFuncionarioCatalogo.desconto,
      mesReferencia: mesReferencia,
    );
  }

  double totalBonus(int funcionarioId, {DateTime? mesReferencia}) {
    return _somarTipo(
      funcionarioId,
      LancamentoFuncionarioCatalogo.bonus,
      mesReferencia: mesReferencia,
    );
  }

  double _somarTipo(
    int funcionarioId,
    String tipo, {
    DateTime? mesReferencia,
  }) {
    return listarPorFuncionario(funcionarioId, mesReferencia: mesReferencia)
        .where((l) => !l.estornado && l.tipo == tipo)
        .fold<double>(0, (acc, l) => acc + l.valor);
  }

  /// Importa [Funcionario.valesJson] e [historicoFinanceiro] legados uma vez.
  bool migrarLegadoSeNecessario(Funcionario f) {
    if (f.id <= 0) return false;
    if (listarPorFuncionario(f.id).isNotEmpty) return false;

    var inseriu = false;

    final valesRaw = f.valesJson.trim();
    if (valesRaw.isNotEmpty && valesRaw != '[]') {
      try {
        final decoded = jsonDecode(valesRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final map = item.cast<String, dynamic>();
            final valor = (map['valor'] as num?)?.toDouble() ?? 0;
            if (valor <= 0) continue;
            final dataStr = map['data'] as String? ?? '';
            final data = DateTime.tryParse(dataStr) ?? DateTime.now();
            salvar(
              LancamentoFuncionario(
                tipo: LancamentoFuncionarioCatalogo.vale,
                valor: valor,
                observacao: (map['observacao'] ?? '').toString(),
                data: data,
              ),
              f.id,
            );
            inseriu = true;
          }
        }
      } catch (_) {
        // ignora JSON invalido
      }
    }

    final hist = f.historicoFinanceiro.trim();
    if (hist.isNotEmpty) {
      salvar(
        LancamentoFuncionario(
          tipo: LancamentoFuncionarioCatalogo.observacao,
          valor: 0,
          observacao: '[Legado] $hist',
          data: DateTime.now(),
        ),
        f.id,
      );
      inseriu = true;
    }

    if (inseriu) {
      f.valesJson = '[]';
      f.historicoFinanceiro = '';
      f.adiantamentoAtual = totalValesAtivos(f.id);
      _db.funcionarioBox.put(f);
    }
    return inseriu;
  }
}

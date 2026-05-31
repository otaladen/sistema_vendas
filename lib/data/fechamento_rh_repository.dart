import '../model/fechamento_rh_funcionario.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class FechamentoRhRepository {
  FechamentoRhRepository(this._db);

  final ObjectBox _db;

  static DateTime normalizarMes(DateTime d) =>
      DateTime(d.year, d.month, 1);

  FechamentoRhFuncionario? obter(int funcionarioId, DateTime mesReferencia) {
    if (funcionarioId <= 0) return null;
    final mes = normalizarMes(mesReferencia);
    final q = _db.fechamentoRhFuncionarioBox
        .query(
          FechamentoRhFuncionario_.funcionarioId.equals(funcionarioId) &
              FechamentoRhFuncionario_.mesReferencia.equalsDate(mes),
        )
        .build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  List<FechamentoRhFuncionario> listarPorMes(DateTime mesReferencia) {
    final mes = normalizarMes(mesReferencia);
    final q = _db.fechamentoRhFuncionarioBox
        .query(FechamentoRhFuncionario_.mesReferencia.equalsDate(mes))
        .order(FechamentoRhFuncionario_.funcionarioId)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<FechamentoRhFuncionario> listarPorFuncionario(int funcionarioId) {
    if (funcionarioId <= 0) return [];
    final q = _db.fechamentoRhFuncionarioBox
        .query(FechamentoRhFuncionario_.funcionarioId.equals(funcionarioId))
        .order(FechamentoRhFuncionario_.mesReferencia, flags: Order.descending)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  int salvar(FechamentoRhFuncionario fechamento) {
    fechamento.mesReferencia = normalizarMes(fechamento.mesReferencia);
    final id = _db.fechamentoRhFuncionarioBox.put(fechamento);
    notificarAlteracaoParaRede(
      entidade: 'fechamento_rh_funcionario',
      entidadeId: id,
    );
    return id;
  }

  bool remover(int id) {
    final ok = _db.fechamentoRhFuncionarioBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('fechamento_rh_funcionario', id);
    }
    return ok;
  }

  void removerPorFuncionario(int funcionarioId) {
    final lista = listarPorFuncionario(funcionarioId);
    if (lista.isEmpty) return;
    for (final f in lista) {
      registrarDeleteParaRede('fechamento_rh_funcionario', f.id);
    }
    _db.fechamentoRhFuncionarioBox.removeMany(lista.map((e) => e.id).toList());
    notificarAlteracaoParaRede(
      entidade: 'fechamento_rh_funcionario',
      entidadeId: 0,
    );
  }
}

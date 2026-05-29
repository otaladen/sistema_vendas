import '../model/funcionario.dart';
import '../objectbox.g.dart';
import 'lancamento_funcionario_repository.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class FuncionarioRepository {
  FuncionarioRepository(this._db, [LancamentoFuncionarioRepository? lancamentos])
      : _lancamentos = lancamentos ?? LancamentoFuncionarioRepository(_db);

  final ObjectBox _db;
  final LancamentoFuncionarioRepository _lancamentos;

  List<Funcionario> listarTodos() {
    final query = _db.funcionarioBox
        .query()
        .order(Funcionario_.nomeCompleto)
        .build();
    final lista = query.find();
    query.close();
    return lista;
  }

  List<Funcionario> pesquisar(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) {
      return listarTodos();
    }
    return listarTodos().where((f) {
      final campos = [
        f.codigoInterno,
        f.nomeCompleto,
        f.cargo,
        f.setor,
        f.funcao,
        f.funcaoOutro,
        f.cpf,
        f.telefone,
        f.whatsapp,
        f.cidade,
        f.contatoEmergenciaNome,
      ].map((e) => e.toLowerCase());
      return campos.any((c) => c.contains(t));
    }).toList();
  }

  int salvar(Funcionario funcionario) {
    final id = _db.funcionarioBox.put(funcionario);
    notificarAlteracaoParaRede(entidade: 'funcionario', entidadeId: id);
    return id;
  }

  bool remover(int id) {
    _lancamentos.removerPorFuncionario(id);
    final ok = _db.funcionarioBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('funcionario', id);
    }
    return ok;
  }

  LancamentoFuncionarioRepository get lancamentos => _lancamentos;

  Funcionario? obterPorId(int id) => _db.funcionarioBox.get(id);

  bool existeCpfParaOutro({
    required String cpfSomenteDigitos,
    required int ignorarId,
  }) {
    final cpf = cpfSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) return false;
    for (final f in listarTodos()) {
      if (f.id == ignorarId) continue;
      final outro = f.cpf.replaceAll(RegExp(r'\D'), '');
      if (outro == cpf) return true;
    }
    return false;
  }

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) {
      return false;
    }
    for (final f in listarTodos()) {
      if (f.id != ignorarId && f.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }

  String proximoCodigoInterno() {
    final funcionarios = listarTodos();
    var maior = 0;
    for (final f in funcionarios) {
      final digits = f.codigoInterno.replaceAll(RegExp(r'\D'), '');
      final numero = int.tryParse(digits);
      if (numero != null && numero > maior) {
        maior = numero;
      }
    }
    return (maior + 1).toString();
  }
}

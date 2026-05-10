import '../model/motorista.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class MotoristaRepository {
  MotoristaRepository(this._db);

  final ObjectBox _db;

  List<Motorista> listarTodos() {
    final query = _db.motoristaBox.query().order(Motorista_.nome).build();
    final lista = query.find();
    query.close();
    return lista;
  }

  List<Motorista> listarAtivos() {
    return listarTodos().where((m) => m.ativo).toList();
  }

  List<Motorista> pesquisar(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return listarTodos();
    return listarTodos().where((m) {
      return m.nome.toLowerCase().contains(t) ||
          m.telefone.toLowerCase().contains(t);
    }).toList();
  }

  int salvar(Motorista motorista) {
    final id = _db.motoristaBox.put(motorista);
    notificarAlteracaoParaRede();
    return id;
  }

  bool remover(int id) {
    final ok = _db.motoristaBox.remove(id);
    if (ok) {
      notificarAlteracaoParaRede();
    }
    return ok;
  }

  bool existeNomeParaOutro({
    required String nomeNormalizado,
    required int ignorarId,
  }) {
    final n = nomeNormalizado.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final m in listarTodos()) {
      if (m.id != ignorarId && m.nome.trim().toLowerCase() == n) {
        return true;
      }
    }
    return false;
  }
}

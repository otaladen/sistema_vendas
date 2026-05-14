import '../model/cliente.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

class ClienteRepository {
  ClienteRepository(this._db);

  final ObjectBox _db;

  List<Cliente> listarTodos() {
    final query = _db.clienteBox.query().order(Cliente_.nomeRazao).build();
    final clientes = query.find();
    query.close();
    return clientes;
  }

  List<Cliente> pesquisar(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) {
      return listarTodos();
    }
    return listarTodos().where((cliente) {
      final campos = [
        cliente.nomeRazao,
        cliente.nomeFantasia,
        cliente.documento,
        cliente.rg,
        cliente.ocupacao,
        cliente.telefone,
        cliente.whatsapp,
        cliente.email,
        cliente.cidade,
      ].map((e) => e.toLowerCase());
      return campos.any((c) => c.contains(t));
    }).toList();
  }

  int salvar(Cliente cliente) {
    final id = _db.clienteBox.put(cliente);
    notificarAlteracaoParaRede();
    return id;
  }

  bool remover(int id) {
    final ok = _db.clienteBox.remove(id);
    if (ok) {
      notificarAlteracaoParaRede();
    }
    return ok;
  }

  Cliente? obterPorId(int id) => _db.clienteBox.get(id);
}

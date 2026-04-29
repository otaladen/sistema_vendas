import '../model/vendedor.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';

class VendedorRepository {
  VendedorRepository(this._db);

  final ObjectBox _db;

  List<Vendedor> listarTodos() {
    final query = _db.vendedorBox.query().order(Vendedor_.nomeCompleto).build();
    final lista = query.find();
    query.close();
    return lista;
  }

  List<Vendedor> listarAtivos() => listarTodos().where((v) => v.ativo).toList();

  List<Vendedor> pesquisar(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) {
      return listarTodos();
    }
    return listarTodos().where((v) {
      final campos = [
        v.codigoInterno,
        v.nomeCompleto,
        v.apelido,
        v.telefone,
        v.whatsapp,
        v.email,
      ].map((e) => e.toLowerCase());
      return campos.any((c) => c.contains(t));
    }).toList();
  }

  int salvar(Vendedor vendedor) => _db.vendedorBox.put(vendedor);

  bool remover(int id) => _db.vendedorBox.remove(id);

  Vendedor? obterPorId(int id) => _db.vendedorBox.get(id);

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) {
      return false;
    }
    for (final v in listarTodos()) {
      if (v.id != ignorarId && v.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }
}

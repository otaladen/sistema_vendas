import '../domain/usuario_senha_codec.dart';
import '../model/vendedor.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

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

  int salvar(Vendedor vendedor) {
    final id = _db.vendedorBox.put(vendedor);
    notificarAlteracaoParaRede(entidade: 'vendedor', entidadeId: id);
    return id;
  }

  bool remover(int id) {
    final ok = _db.vendedorBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('vendedor', id);
    }
    return ok;
  }

  Vendedor? obterPorId(int id) => _db.vendedorBox.get(id);

  bool temSenhaPdvConfigurada(Vendedor vendedor) =>
      vendedor.senhaPdv.trim().isNotEmpty;

  /// Identifica vendedor ativo pela senha do terminal. Null se invalida ou ambigua.
  Vendedor? autenticarPorSenhaPdv(String senhaPlain) {
    final senha = senhaPlain.trim();
    if (senha.isEmpty) return null;

    Vendedor? unico;
    for (final v in listarAtivos()) {
      if (!temSenhaPdvConfigurada(v)) continue;
      if (!UsuarioSenhaCodec.verificar(senha, v.senhaPdv)) continue;
      if (unico != null) return null;
      unico = v;
    }
    return unico;
  }

  int contarAtivosComSenhaPdv() =>
      listarAtivos().where(temSenhaPdvConfigurada).length;

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

  /// Valor numerico extraido de [codigoInterno] (ex.: `12`, `V03` -> 3). Null se nao houver digitos.
  static int? codigoInternoComoInteiro(String codigoInterno) {
    final t = codigoInterno.trim();
    if (t.isEmpty) return null;
    final direto = int.tryParse(t);
    if (direto != null) return direto;
    final m = RegExp(r'\d+').firstMatch(t);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  /// Proximo codigo sugerido na sequencia 1, 2, 3… com base no maior numero ja usado.
  int proximoCodigoInternoSequencial() {
    var maxN = 0;
    for (final v in listarTodos()) {
      final n = codigoInternoComoInteiro(v.codigoInterno);
      if (n != null && n > maxN) maxN = n;
    }
    return maxN + 1;
  }
}

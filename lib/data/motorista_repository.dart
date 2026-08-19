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
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    return listarTodos().where((m) {
      if (m.nome.toLowerCase().contains(t) ||
          m.telefone.toLowerCase().contains(t) ||
          m.codigoInterno.toLowerCase().contains(t) ||
          m.cpf.toLowerCase().contains(t) ||
          m.cnhNumero.toLowerCase().contains(t) ||
          m.cnhCategoria.toLowerCase().contains(t)) {
        return true;
      }
      if (digitos.isEmpty) return false;
      final nums = [
        m.telefone,
        m.cpf,
        m.cnhNumero,
      ].map((s) => s.replaceAll(RegExp(r'\D'), ''));
      return nums.any((n) => n.contains(digitos));
    }).toList();
  }

  Motorista? obterPorId(int id) => _db.motoristaBox.get(id);

  int salvar(Motorista motorista) {
    final id = _db.motoristaBox.put(motorista);
    notificarAlteracaoParaRede(entidade: 'motorista', entidadeId: id);
    return id;
  }

  bool remover(int id) {
    final ok = _db.motoristaBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('motorista', id);
    }
    return ok;
  }

  String proximoCodigoInterno() {
    var maior = 0;
    for (final m in listarTodos()) {
      final digits = m.codigoInterno.replaceAll(RegExp(r'\D'), '');
      final n = int.tryParse(digits);
      if (n != null && n > maior) maior = n;
    }
    return (maior + 1).toString();
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

  bool existeCodigoParaOutro({
    required String codigoNormalizado,
    required int ignorarId,
  }) {
    final c = codigoNormalizado.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final m in listarTodos()) {
      if (m.id != ignorarId && m.codigoInterno.trim().toLowerCase() == c) {
        return true;
      }
    }
    return false;
  }

  bool existeCpfParaOutro({
    required String cpfSomenteDigitos,
    required int ignorarId,
  }) {
    final cpf = cpfSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) return false;
    for (final m in listarTodos()) {
      if (m.id == ignorarId) continue;
      if (m.cpf.replaceAll(RegExp(r'\D'), '') == cpf) return true;
    }
    return false;
  }

  bool existeCnhParaOutro({
    required String cnhSomenteDigitos,
    required int ignorarId,
  }) {
    final cnh = cnhSomenteDigitos.replaceAll(RegExp(r'\D'), '');
    if (cnh.isEmpty) return false;
    for (final m in listarTodos()) {
      if (m.id == ignorarId) continue;
      if (m.cnhNumero.replaceAll(RegExp(r'\D'), '') == cnh) return true;
    }
    return false;
  }
}

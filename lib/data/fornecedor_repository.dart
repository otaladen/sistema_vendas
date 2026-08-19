import '../model/fornecedor_nfe.dart';
import '../objectbox.g.dart';
import 'objectbox.dart';
import 'sync/sync_write_trigger.dart';

/// Persistencia do cadastro de fornecedores ([FornecedorNfe]).
class FornecedorRepository {
  FornecedorRepository(this._db);

  final ObjectBox _db;

  Box<FornecedorNfe> get _box => _db.fornecedorNfeBox;

  static String somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  List<FornecedorNfe> listarTodos({bool apenasAtivos = false}) {
    final todos = _box.getAll();
    final lista = apenasAtivos ? todos.where((f) => f.ativo).toList() : todos;
    lista.sort((a, b) => a.nomeExibicao.toLowerCase().compareTo(
          b.nomeExibicao.toLowerCase(),
        ));
    return lista;
  }

  List<FornecedorNfe> pesquisar(String termo, {bool apenasAtivos = false}) {
    final t = termo.trim().toLowerCase();
    final dig = somenteDigitos(termo);
    final base = listarTodos(apenasAtivos: apenasAtivos);
    if (t.isEmpty && dig.isEmpty) return base;
    return base.where((f) {
      if (t.isNotEmpty) {
        final campos = [
          f.razaoSocial,
          f.nomeFantasia,
          f.cidade,
          f.email,
          f.telefone,
          f.whatsapp,
        ].map((e) => e.toLowerCase());
        if (campos.any((c) => c.contains(t))) return true;
      }
      if (dig.isNotEmpty) {
        final docs = [
          somenteDigitos(f.cnpj),
          somenteDigitos(f.telefone),
          somenteDigitos(f.whatsapp),
          somenteDigitos(f.cep),
        ];
        if (docs.any((d) => d.contains(dig))) return true;
      }
      return false;
    }).toList();
  }

  FornecedorNfe? obterPorId(int id) => _box.get(id);

  FornecedorNfe? obterPorCnpj(String cnpjOuDoc) {
    final dig = somenteDigitos(cnpjOuDoc);
    if (dig.isEmpty) return null;
    final q = _box.query(FornecedorNfe_.cnpj.equals(dig)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  /// Insere ou atualiza. Se [cnpj] ja existir, atualiza o registro (merge).
  int salvar(FornecedorNfe fornecedor) {
    var dig = somenteDigitos(fornecedor.cnpj);
    if (dig.isEmpty && fornecedor.cnpj.startsWith('MANUAL_')) {
      dig = fornecedor.cnpj;
    } else if (dig.isEmpty) {
      throw ArgumentError('Informe CNPJ/CPF do fornecedor.');
    } else {
      fornecedor.cnpj = dig;
    }
    if (fornecedor.razaoSocial.trim().isEmpty) {
      throw ArgumentError('Informe a razao social.');
    }

    final existente = dig.startsWith('MANUAL_')
        ? null
        : obterPorCnpj(dig);
    if (existente != null &&
        (fornecedor.id == 0 || fornecedor.id != existente.id)) {
      if (fornecedor.id == 0) {
        fornecedor.id = existente.id;
      } else {
        throw StateError('Ja existe fornecedor com este CNPJ/CPF.');
      }
    }

    fornecedor.atualizadoEm = DateTime.now().toUtc();
    final id = _box.put(fornecedor);
    fornecedor.id = id;
    notificarAlteracaoParaRede(entidade: 'fornecedor_nfe', entidadeId: id);
    return id;
  }

  bool remover(int id) {
    final ok = _box.remove(id);
    if (ok) {
      notificarAlteracaoParaRede(entidade: 'fornecedor_nfe', entidadeId: id);
    }
    return ok;
  }
}

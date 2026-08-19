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

  /// Busca indexada no ObjectBox (evita carregar todos os clientes na RAM).
  /// Pagina clientes ordenados por nome (telas operacionais; evita [listarTodos]).
  List<Cliente> listarPaginado({
    int offset = 0,
    int limit = 80,
    bool somenteAtivos = false,
  }) {
    if (limit <= 0) return const [];
    final qb = somenteAtivos
        ? _db.clienteBox.query(Cliente_.ativo.equals(true))
        : _db.clienteBox.query();
    final query = qb.order(Cliente_.nomeRazao).build();
    try {
      query.offset = offset < 0 ? 0 : offset;
      query.limit = limit;
      return query.find();
    } finally {
      query.close();
    }
  }

  List<Cliente> pesquisar(String termo) {
    final t = termo.trim();
    if (t.isEmpty) {
      return const [];
    }
    final lower = t.toLowerCase();
    final digitos = t.replaceAll(RegExp(r'\D'), '');
    final cond = _condicaoPesquisaCliente(lower);
    final query =
        _db.clienteBox.query(cond).order(Cliente_.nomeRazao).build();
    try {
      final lista = query.find();
      // CPF/CNPJ digitado sem mascara: ObjectBox contains nao acha "123.456...".
      if (digitos.length < 3) return lista;
      final ids = lista.map((c) => c.id).toSet();
      for (final c in _db.clienteBox.getAll()) {
        if (ids.contains(c.id)) continue;
        final docs = [
          c.documento,
          c.telefone,
          c.whatsapp,
          c.cep,
        ].map((s) => s.replaceAll(RegExp(r'\D'), ''));
        if (docs.any((d) => d.contains(digitos))) {
          lista.add(c);
          ids.add(c.id);
        }
      }
      return lista;
    } finally {
      query.close();
    }
  }

  /// Termo ja normalizado em minusculas; usado por [pesquisar].
  Condition<Cliente> _condicaoPesquisaCliente(String lower) {
    return Cliente_.nomeRazao
        .contains(lower, caseSensitive: false)
        .or(Cliente_.nomeFantasia.contains(lower, caseSensitive: false))
        .or(Cliente_.documento.contains(lower, caseSensitive: false))
        .or(Cliente_.rg.contains(lower, caseSensitive: false))
        .or(Cliente_.ocupacao.contains(lower, caseSensitive: false))
        .or(Cliente_.telefone.contains(lower, caseSensitive: false))
        .or(Cliente_.whatsapp.contains(lower, caseSensitive: false))
        .or(Cliente_.email.contains(lower, caseSensitive: false))
        .or(Cliente_.cidade.contains(lower, caseSensitive: false))
        .or(Cliente_.codigoInterno.contains(lower, caseSensitive: false))
        .or(Cliente_.segmento.contains(lower, caseSensitive: false));
  }

  int salvar(Cliente cliente) {
    final id = _db.clienteBox.put(cliente);
    notificarAlteracaoParaRede(entidade: 'cliente', entidadeId: id);
    return id;
  }

  bool remover(int id) {
    final ok = _db.clienteBox.remove(id);
    if (ok) {
      registrarDeleteParaRede('cliente', id);
    }
    return ok;
  }

  Cliente? obterPorId(int id) => _db.clienteBox.get(id);
}

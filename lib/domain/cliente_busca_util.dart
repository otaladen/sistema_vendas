import '../model/cliente.dart';

String _somenteDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

/// [clienteRepository] e dynamic; normaliza retorno de listar/pesquisar.
List<Cliente> listaClientesDeRepositorio(dynamic raw) {
  if (raw is List<Cliente>) return raw;
  if (raw is Iterable<Cliente>) return raw.toList();
  return List<Cliente>.from(raw as Iterable);
}

/// Match de cliente por nome, documento, telefone etc. (cache ou fallback em memoria).
bool clienteCorrespondeTermoBusca(Cliente c, String termo) {
  final t = termo.trim().toLowerCase();
  if (t.isEmpty) return true;
  final campos = [
    c.nomeRazao,
    c.nomeFantasia,
    c.documento,
    c.rg,
    c.ocupacao,
    c.telefone,
    c.whatsapp,
    c.email,
    c.cidade,
    c.codigoInterno,
    c.segmento,
  ].map((e) => e.toLowerCase());
  if (campos.any((campo) => campo.contains(t))) return true;
  final digitos = _somenteDigitos(termo);
  if (digitos.length < 3) return false;
  final nums = [
    c.documento,
    c.telefone,
    c.whatsapp,
    c.cep,
  ].map(_somenteDigitos);
  return nums.any((n) => n.contains(digitos));
}

List<Cliente> filtrarClientesPorTermo(
  Iterable<Cliente> base,
  String termo, {
  bool somenteAtivos = false,
  int? limit,
}) {
  final t = termo.trim();
  Iterable<Cliente> out = base;
  if (somenteAtivos) {
    out = out.where((c) => c.ativo);
  }
  if (t.isNotEmpty) {
    out = out.where((c) => clienteCorrespondeTermoBusca(c, t));
  }
  final lista = out.toList()
    ..sort(
      (a, b) => a.nomeRazao.toLowerCase().compareTo(b.nomeRazao.toLowerCase()),
    );
  if (limit != null && limit > 0 && lista.length > limit) {
    return lista.sublist(0, limit);
  }
  return lista;
}
